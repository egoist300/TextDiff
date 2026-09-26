#Requires -Version 5.1

function ConvertTo-DiffText {
    <#
    .SYNOPSIS
        対応付けの結果を、コンソール表示用の行に変換する。
    .DESCRIPTION
        各行は、行番号とマーカーの見出し（Gutter）と、本文の断片（Segments）で構成されます。
        断片は行内の変更箇所で分割されており、Changed が $true の断片を別の色で表示できます。

        変更行の前後 ContextLine 行だけを残し、それ以外は 1 行の省略行にまとめます。

        コンソールへの出力はしません。表示の色と、省略行の文言（「N 行省略」など）は呼び出し側で決めます。
    .PARAMETER Rows
        Get-DiffAlignment が返す行の対応付け（TextDiff.DiffRow の配列）。それ以外は受け付けません。
    .PARAMETER ContextLine
        変更行の前後に残す、共通行の数（0〜100）。
    .OUTPUTS
        TextDiff.TextLine。次の項目を持つ [PSCustomObject] の配列です。
            Gutter       = '   6- '  行番号とマーカー
            Role         = 'Removed' | 'Added' | 'Context' | 'Omitted'
            Segments     = TextDiff.Segment（[PSCustomObject]@{ Text; Changed }）の配列
            OmittedCount = 省略した行数。Omitted 以外の行では 0
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

        削除行と追加行の 2 行を表示し、変更箇所（100 と 20）だけを黄色にします。
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
    # 変更行から ContextLine 行以内の行だけを残す。1000 行のうち 5 行の変更で 995 行の文脈を表示すると、
    # 差分が読みにくくなるため（git diff と同じ方式）。
    # ConvertTo-DiffHtml は証跡として全体を残すため、行を省略しない。
    $keep = New-Object -TypeName 'bool[]' -ArgumentList $Rows.Count
    for ($rowIndex = 0; $rowIndex -lt $Rows.Count; $rowIndex++) {
        if ($Rows[$rowIndex].Kind -ceq 'Same') { continue }
        $from = [Math]::Max(0, $rowIndex - $ContextLine)
        $to = [Math]::Min($Rows.Count - 1, $rowIndex + $ContextLine)
        for ($keepIndex = $from; $keepIndex -le $to; $keepIndex++) { $keep[$keepIndex] = $true }
    }

    # --- 行番号の桁数を揃える ---
    # 途中で桁数が変わると行の位置がずれ、差分より目立つため。
    $maxNo = 0
    foreach ($row in $Rows) {
        foreach ($no in @($row.LeftNo, $row.RightNo)) {
            if ($null -ne $no -and $no -gt $maxNo) { $maxNo = $no }
        }
    }
    $noWidth = [Math]::Max(3, ([string]$maxNo).Length)

    $index = 0
    while ($index -lt $Rows.Count) {
        if (-not $keep[$index]) {
            # 連続する非表示行を、1 行の省略行にまとめる。
            $start = $index
            while ($index -lt $Rows.Count -and -not $keep[$index]) { $index++ }
            $output.Add((ConvertTo-DiffTextLine -Gutter ('  ' + ('.' * $noWidth) + '  ') -Role 'Omitted' -OmittedCount ($index - $start)))
            continue
        }

        $row = $Rows[$index]
        switch -CaseSensitive ($row.Kind) {
            'Same' {
                $output.Add((ConvertTo-DiffTextLine -Gutter (Format-DiffGutter -Number $row.RightNo -Marker ' ' -Width $noWidth) -Role 'Context' -Text $row.Right))
            }
            'Changed' {
                # 行内の変更箇所を求め、削除行と追加行の 2 行として出力する。
                $inline = Get-InlineDiff -Left $row.Left -Right $row.Right
                $output.Add((ConvertTo-DiffTextLine -Gutter (Format-DiffGutter -Number $row.LeftNo -Marker '-' -Width $noWidth) -Role 'Removed' -Segments $inline.Left))
                $output.Add((ConvertTo-DiffTextLine -Gutter (Format-DiffGutter -Number $row.RightNo -Marker '+' -Width $noWidth) -Role 'Added' -Segments $inline.Right))
            }
            'Deleted' {
                $output.Add((ConvertTo-DiffTextLine -Gutter (Format-DiffGutter -Number $row.LeftNo -Marker '-' -Width $noWidth) -Role 'Removed' -Text $row.Left))
            }
            'Added' {
                $output.Add((ConvertTo-DiffTextLine -Gutter (Format-DiffGutter -Number $row.RightNo -Marker '+' -Width $noWidth) -Role 'Added' -Text $row.Right))
            }
        }
        $index++
    }

    return $output.ToArray()
}
