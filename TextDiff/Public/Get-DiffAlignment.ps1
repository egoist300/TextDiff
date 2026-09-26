#Requires -Version 5.1

function Get-DiffAlignment {
    <#
    .SYNOPSIS
        変更前と変更後の行を対応付け、行ごとの差分の種類を返す。
    .DESCRIPTION
        Myers 法で共通行を確定し、隣接する削除行と追加行のうち、類似度が SimilarityThreshold 以上の組を
        1 行の変更（Changed）として対応付けます。
    .PARAMETER BeforeLines
        変更前の行の配列。空の配列と空行を含められます。
    .PARAMETER AfterLines
        変更後の行の配列。空の配列と空行を含められます。
    .PARAMETER SimilarityThreshold
        削除行と追加行を Changed として対応付ける類似度の下限（0.0〜1.0）。
        既定の 0.5 は、行の半分以上が共通なら同じ行の変更とみなすことを表します。
    .OUTPUTS
        TextDiff.DiffRow。次の項目を持つ [PSCustomObject] を、変更前・変更後の並び順で返します。
            Kind    = 'Same' | 'Changed' | 'Deleted' | 'Added'
            LeftNo  = 変更前の行番号（1 始まり）。Added のときは $null
            RightNo = 変更後の行番号（1 始まり）。Deleted のときは $null
            Left    = 変更前の行の内容。Added のときは $null
            Right   = 変更後の行の内容。Deleted のときは $null
        ConvertTo-DiffText と ConvertTo-DiffHtml は、この型のものだけを受け付けます。
    .EXAMPLE
        PS> $rows = Get-DiffAlignment -BeforeLines @('id bigint,', 'name varchar(100),') -AfterLines @('id bigint,', 'name varchar(20),')
        PS> $rows | ForEach-Object -Process { $_.Kind }
        Same
        Changed

        2 行目は同じ行の変更として、1 つの Changed になります。
    #>
    [CmdletBinding()]
    [OutputType('TextDiff.DiffRow')]
    param(
        # NOTE: AllowEmptyString が必須（理由は ConvertTo-LineId のコメントを参照）。
        [Parameter(Mandatory)] [AllowEmptyCollection()] [AllowEmptyString()] [string[]]$BeforeLines,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [AllowEmptyString()] [string[]]$AfterLines,
        [ValidateRange(0.0, 1.0)] [double]$SimilarityThreshold = 0.5
    )

    # Compare-Object ではなく Myers 法を使うのは、行の順序を保って比較するため。Compare-Object は集合の比較で、
    # どの行がどの行に変更されたかを示せない。
    # 動的計画法（O(N×M)）ではなく Myers 法（O((N+M)×D)）にするのは、変更が少ないほど速いため。
    # 1000 行のうち 5 行の変更で、動的計画法の 2,801 ミリ秒に対して 14 ミリ秒だった（Windows PowerShell 5.1 での実測）。
    # 共通の先頭・末尾を除去してから動的計画法を実行する方法も試したが、変更行が全体に散らばる場合は
    # ほとんど除去できず、効果が無かった。
    $ids = ConvertTo-LineId -Left $BeforeLines -Right $AfterLines
    # 空のリストは $null で返り、StrictMode では $ops.Count が例外になる。
    $ops = @(Get-MyersOperation -Left $ids.Left -Right $ids.Right)

    $result = [System.Collections.Generic.List[object]]::new()
    $index = 0
    while ($index -lt $ops.Count) {
        $op = $ops[$index]

        if ($op.Kind -ceq 'Same') {
            $result.Add([PSCustomObject]@{
                    PSTypeName = 'TextDiff.DiffRow'
                    Kind       = 'Same'
                    LeftNo     = $op.LeftIndex + 1
                    RightNo    = $op.RightIndex + 1
                    Left       = $BeforeLines[$op.LeftIndex]
                    Right      = $AfterLines[$op.RightIndex]
                })
            $index++
            continue
        }

        # 連続する削除と追加を 1 つのブロックとして取り出す。Myers 法の出力では削除が追加より先に並ぶとは
        # 限らないため、ブロック内で分類してから対応付ける。
        $deleted = [System.Collections.Generic.List[int]]::new()
        $added = [System.Collections.Generic.List[int]]::new()
        while ($index -lt $ops.Count -and $ops[$index].Kind -cne 'Same') {
            if ($ops[$index].Kind -ceq 'Deleted') { $deleted.Add($ops[$index].LeftIndex) }
            else { $added.Add($ops[$index].RightIndex) }
            $index++
        }

        # ブロック内で、削除行と追加行を先頭から順に 1 対 1 で比較する。
        # 隣接しているだけで対応付けると、別々の変更（列の削除と別の列の追加など）を 1 行の変更と誤認し、
        # 行内の強調が行のほぼ全体に付いて読めなくなる。そのため類似度で判定する。
        $pairCount = [Math]::Min($deleted.Count, $added.Count)
        $usedLeft = New-Object -TypeName 'bool[]' -ArgumentList $deleted.Count
        $usedRight = New-Object -TypeName 'bool[]' -ArgumentList $added.Count
        $pending = [System.Collections.Generic.List[hashtable]]::new()

        for ($pairIndex = 0; $pairIndex -lt $pairCount; $pairIndex++) {
            $leftIndex = $deleted[$pairIndex]
            $rightIndex = $added[$pairIndex]
            $similarity = Get-LineSimilarity -Left $BeforeLines[$leftIndex] -Right $AfterLines[$rightIndex]
            if ($similarity -ge $SimilarityThreshold) {
                $usedLeft[$pairIndex] = $true
                $usedRight[$pairIndex] = $true
                $pending.Add(@{
                        Kind    = 'Changed'
                        LeftNo  = $leftIndex + 1
                        RightNo = $rightIndex + 1
                        Left    = $BeforeLines[$leftIndex]
                        Right   = $AfterLines[$rightIndex]
                        Order   = $pairIndex
                    })
            }
        }

        # 対応付けなかった行を、元の順序のまま並べる。
        # 削除行を追加行より先に置くのは、diff の慣習（- が先、+ が後）に合わせるため。
        for ($deletedIndex = 0; $deletedIndex -lt $deleted.Count; $deletedIndex++) {
            if ($usedLeft[$deletedIndex]) { continue }
            $pending.Add(@{
                    Kind    = 'Deleted'
                    LeftNo  = $deleted[$deletedIndex] + 1
                    RightNo = $null
                    Left    = $BeforeLines[$deleted[$deletedIndex]]
                    Right   = $null
                    Order   = $deletedIndex
                })
        }
        for ($addedIndex = 0; $addedIndex -lt $added.Count; $addedIndex++) {
            if ($usedRight[$addedIndex]) { continue }
            $pending.Add(@{
                    Kind    = 'Added'
                    LeftNo  = $null
                    RightNo = $added[$addedIndex] + 1
                    Left    = $null
                    Right   = $AfterLines[$added[$addedIndex]]
                    Order   = $addedIndex + 0.5
                })
        }

        # 並べ替え用の Order は、戻り値に含めない。
        foreach ($entry in ($pending | Sort-Object -CaseSensitive -Property { $_.Order })) {
            $result.Add([PSCustomObject]@{
                    PSTypeName = 'TextDiff.DiffRow'
                    Kind       = $entry.Kind
                    LeftNo     = $entry.LeftNo
                    RightNo    = $entry.RightNo
                    Left       = $entry.Left
                    Right      = $entry.Right
                })
        }
    }

    return $result.ToArray()
}
