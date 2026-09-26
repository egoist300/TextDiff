#Requires -Version 5.1

# 対応づけの結果を、コンソールに出す形へ変換する処理。
#
# 【なぜ文字列ではなく構造を返すか】
# 行内の変わった部分だけ色を変えるため、1 行を「断片の並び」として渡す必要がある。
# 文字列にしてしまうと、どこを別の色にすべきかの情報が失われる。
# 出力（Write-Host）は呼び出し側が行う。ここは表示内容を決めるだけに留めることで、
# テストがコンソール出力の捕捉ではなく、ただのデータ比較で済む。
# 畳んだ行の文言（「N 行省略」など）も呼び出し側が作る。ここは行数だけを返す。
# 文言と色は使う側の画面の決まりに合わせるものなので、このモジュールは持たない。
#
# 【なぜ文脈行を絞るか】
# 変わっていない行をすべて前後に並べる形は、数十行の定義なら読みやすいが、
# 1000 行のデータのうち 5 行が変わっただけで 995 行の文脈が流れると、
# 差分の行だけを出すより読みにくくなる。
# git diff と同じく前後数行に絞り、離れた変更の間は「N 行省略」で畳む。
#
# HTML 側（ConvertTo-DiffHtml）は畳まない。あちらはスクロールできるうえ、
# 証跡としては全体が残っている方がよいため。読む人も目的も違う。
function ConvertTo-DiffText {
    <#
    .SYNOPSIS
        対応づけの結果を、コンソール表示用の行の並びに変換する。
    .DESCRIPTION
        1 行は「行番号などの見出し（Gutter）」と「本文の断片（Segments）」で構成されます。
        断片は行内の差分で分かれており、Changed が立っている断片だけ別の色で表示します。

        変更のある行の前後 ContextLine 行だけを残し、それ以外は 1 行の省略表示に畳みます。
    .PARAMETER Rows
        Get-DiffAlignment が返す行の対応づけ（TextDiff.DiffRow の配列）。それ以外は受け付けません。
    .PARAMETER ContextLine
        変更のある行の前後に残す、変わっていない行の数（0〜100）。
    .OUTPUTS
        TextDiff.TextLine。次の項目を持つ [PSCustomObject] の配列です。
            Gutter       = '   6- '  行番号とマーカー
            Role         = 'Removed' | 'Added' | 'Context' | 'Omitted'
            Segments     = TextDiff.Segment（[PSCustomObject]@{ Text; Changed }）の配列
            OmittedCount = 畳んだ行数。Omitted 以外の行では 0
        Segments の Text を連結すると、元の行に一致します。Omitted の行だけは Segments が空です。
    .EXAMPLE
        PS> $rows = Get-DiffAlignment -BeforeLines @('name varchar(100),') -AfterLines @('name varchar(20),')
        PS> foreach ($line in ConvertTo-DiffText -Rows $rows) {
        >>     Write-Host -Object $line.Gutter -NoNewline
        >>     foreach ($segment in $line.Segments) {
        >>         $color = if ($segment.Changed) { 'Yellow' } else { 'Gray' }
        >>         Write-Host -Object $segment.Text -ForegroundColor $color -NoNewline
        >>     }
        >>     Write-Host
        >> }

        削除側と追加側の 2 行を出し、行内で変わった部分（100 と 20）だけを黄色にします。
    #>
    [CmdletBinding()]
    [OutputType('TextDiff.TextLine')]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [PSTypeName('TextDiff.DiffRow')] [psobject[]]$Rows,
        [ValidateRange(0, 100)] [int]$ContextLine = 3
    )

    $output = [System.Collections.Generic.List[object]]::new()
    if ($Rows.Count -eq 0) { return $output.ToArray() }

    # --- 表示する行を決める ---
    # 変更のある行から ContextLine 以内の距離にある行だけを残す
    $keep = New-Object -TypeName 'bool[]' -ArgumentList $Rows.Count
    for ($rowIndex = 0; $rowIndex -lt $Rows.Count; $rowIndex++) {
        if ($Rows[$rowIndex].Kind -ceq 'Same') { continue }
        $from = [Math]::Max(0, $rowIndex - $ContextLine)
        $to = [Math]::Min($Rows.Count - 1, $rowIndex + $ContextLine)
        for ($keepIndex = $from; $keepIndex -le $to; $keepIndex++) { $keep[$keepIndex] = $true }
    }

    # --- 行番号の桁を揃える ---
    # 途中で桁が変わると行がガタつき、差分そのものより目に付く
    $maxNo = 0
    foreach ($row in $Rows) {
        foreach ($no in @($row.LeftNo, $row.RightNo)) {
            if ($null -ne $no -and $no -gt $maxNo) { $maxNo = $no }
        }
    }
    $noWidth = [Math]::Max(3, ([string]$maxNo).Length)

    function Format-Gutter {
        <#
        .SYNOPSIS
            行番号とマーカーを、桁を揃えた見出しにする。
        .PARAMETER Number
            行番号。反対側にしか無い行では $null で、その桁を空白で埋める。
        .PARAMETER Marker
            '-'（削除側）、'+'（追加側）、' '（文脈行）のいずれか。
        .PARAMETER Width
            行番号の桁数。
        #>
        param([Nullable[int]]$Number, [string]$Marker, [int]$Width)
        $text = if ($null -ne $Number) { ([string]$Number).PadLeft($Width) } else { ' ' * $Width }
        return "  $text$Marker "
    }

    function ConvertTo-TextLine {
        <#
        .SYNOPSIS
            返す 1 行（TextDiff.TextLine）を作る。どの行も同じ項目を持たせるため、ここでだけ作る。
        .PARAMETER Gutter
            行番号とマーカーの見出し。
        .PARAMETER Role
            'Removed' / 'Added' / 'Context' / 'Omitted' のいずれか。
        .PARAMETER Text
            行全体を 1 つの変わっていない断片にするときの本文。Segments を渡すときは使わない。
        .PARAMETER Segments
            行内の差分で分けた断片（TextDiff.Segment の配列）。
        .PARAMETER OmittedCount
            畳んだ行数。Omitted 以外の行では 0。
        #>
        param(
            [string]$Gutter,
            [string]$Role,
            [string]$Text,
            [psobject[]]$Segments = @(),
            [int]$OmittedCount = 0
        )
        $lineSegments = if ($PSBoundParameters.ContainsKey('Text')) {
            [PSCustomObject]@{ PSTypeName = 'TextDiff.Segment'; Text = $Text; Changed = $false }
        }
        else {
            $Segments
        }
        return [PSCustomObject]@{
            PSTypeName   = 'TextDiff.TextLine'
            Gutter       = $Gutter
            Role         = $Role
            Segments     = @($lineSegments)
            OmittedCount = $OmittedCount
        }
    }

    $index = 0
    while ($index -lt $Rows.Count) {
        if (-not $keep[$index]) {
            # 連続する非表示行をまとめて 1 行に畳む
            $start = $index
            while ($index -lt $Rows.Count -and -not $keep[$index]) { $index++ }
            $output.Add((ConvertTo-TextLine -Gutter ('  ' + ('.' * $noWidth) + '  ') -Role 'Omitted' -OmittedCount ($index - $start)))
            continue
        }

        $row = $Rows[$index]
        switch -CaseSensitive ($row.Kind) {
            'Same' {
                $output.Add((ConvertTo-TextLine -Gutter (Format-Gutter -Number $row.RightNo -Marker ' ' -Width $noWidth) -Role 'Context' -Text $row.Right))
            }
            'Changed' {
                # 行内のどこが変わったかを求め、削除側と追加側の 2 行に分けて出す
                $inline = Get-InlineDiff -Left $row.Left -Right $row.Right
                $output.Add((ConvertTo-TextLine -Gutter (Format-Gutter -Number $row.LeftNo -Marker '-' -Width $noWidth) -Role 'Removed' -Segments $inline.Left))
                $output.Add((ConvertTo-TextLine -Gutter (Format-Gutter -Number $row.RightNo -Marker '+' -Width $noWidth) -Role 'Added' -Segments $inline.Right))
            }
            'Deleted' {
                $output.Add((ConvertTo-TextLine -Gutter (Format-Gutter -Number $row.LeftNo -Marker '-' -Width $noWidth) -Role 'Removed' -Text $row.Left))
            }
            'Added' {
                $output.Add((ConvertTo-TextLine -Gutter (Format-Gutter -Number $row.RightNo -Marker '+' -Width $noWidth) -Role 'Added' -Text $row.Right))
            }
        }
        $index++
    }

    return $output.ToArray()
}
