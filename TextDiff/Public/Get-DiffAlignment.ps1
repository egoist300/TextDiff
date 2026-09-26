# before/after の行を対応づける処理。
#
# 【なぜ Compare-Object をやめるのか】
# Compare-Object は集合の比較で、行の順序を持たない。答えられるのは
# 「どちらか片方にしか無い行はどれか」だけで、「6 行目が書き換わった」とは言えない。
# 削除行を全部並べ、その後に追加行を全部並べるしかなく、どれとどれが対なのかは
# 読む人の推測に委ねられる。行数が増えるほど破綻する。
#
# 【なぜ Myers 法か】
# 素朴な動的計画法は O(N×M) で、中身によらず一定の時間がかかる。
# Windows PowerShell 5.1 での実測では 1 セルあたり約 2.6 マイクロ秒で、
# 1000 行 × 1000 行のスナップショットに約 2.8 秒かかった。
#
# Myers 法は O((N+M)×D)（D は編集距離）で、**差分が少ないほど速い**。
# 同じ 1000 行でも、実際のリリースに近い「5 行だけ変更」なら 14 ミリ秒で終わる。
# WinMerge や GNU diff が採用しているのもこの理由による。
#
#   1000 行 /   5 行変更 : 素朴な DP 2,801ms → Myers    14ms
#   1000 行 / 100 行変更 : 素朴な DP 2,830ms → Myers    85ms
#   1000 行 / 全面書換   : 素朴な DP 2,388ms → Myers 1,018ms
#
# 「共通の先頭・末尾を削ってから素朴な DP」も試したが、変更行が全体に散らばると
# ほとんど削れず効果が無かった。行単位では Myers を使う。
# （行内＝文字単位では逆に削り込みが決定的に効く。Get-InlineDiff 参照）

function Get-DiffAlignment {
    <#
    .SYNOPSIS
        before/after の行を対応づけ、1 行ごとの差分の種類を返す。
    .DESCRIPTION
        Myers 法で共通行を確定させたうえで、隣り合った削除と追加のうち
        「同じ行の書き換え」と見なせるものを Changed として対にします。

        対にするかどうかを類似度で判定するのが要点です。素朴に「隣り合った
        削除と追加を対にする」と実装すると、たまたま隣り合っただけの
        別々の変更まで書き換えと誤認します。例えば次は書き換えではなく、
        列の削除と別の列の追加が偶然隣接しただけです。

            -    status_code character(2) NOT NULL,
            +    contact_email_address text,

        これを Changed にすると、行内強調が行のほぼ全体に付いて読めなくなります。
    .PARAMETER BeforeLines
        変更前の行の並び。空の配列と空行を含められます。
    .PARAMETER AfterLines
        変更後の行の並び。空の配列と空行を含められます。
    .PARAMETER SimilarityThreshold
        削除と追加を Changed として対にする類似度の下限（0.0〜1.0）。
        既定 0.5 は「行の半分以上が共通なら同じ行の書き換えとみなす」意味。
    .OUTPUTS
        [hashtable[]]
        @{
            Kind    = 'Same' | 'Changed' | 'Deleted' | 'Added'
            LeftNo  = before の行番号（1 始まり）。Added のときは $null
            RightNo = after の行番号（1 始まり）。Deleted のときは $null
            Left    = before の行の内容。Added のときは $null
            Right   = after の行の内容。Deleted のときは $null
        }
        の配列を、before/after の並び順で返します。
    .EXAMPLE
        PS> $rows = Get-DiffAlignment -BeforeLines @('id bigint,', 'name varchar(100),') -AfterLines @('id bigint,', 'name varchar(20),')
        PS> $rows | ForEach-Object -Process { $_.Kind }
        Same
        Changed

        2 行目は同じ行の書き換えとして、1 つの Changed にまとまります。
    #>
    [CmdletBinding()]
    [OutputType([hashtable[]])]
    param(
        # NOTE: AllowEmptyString が必須（理由は ConvertTo-LineId のコメント参照）
        [Parameter(Mandatory)] [AllowEmptyCollection()] [AllowEmptyString()] [string[]]$BeforeLines,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [AllowEmptyString()] [string[]]$AfterLines,
        [ValidateRange(0.0, 1.0)] [double]$SimilarityThreshold = 0.5
    )

    $ids = ConvertTo-LineId -Left $BeforeLines -Right $AfterLines
    # NOTE: @() で囲むこと。Get-MyersOperation が空のリストを返すと、PowerShell の
    #       出力ストリームがそれを「何も出力しない」に展開してしまい $ops が $null になる。
    #       StrictMode 3.0 下では直後の $ops.Count が
    #       「The property 'Count' cannot be found」で落ちる（before/after が
    #       どちらも空、つまり対象オブジェクトが存在しない場合に実際に起きる）
    $ops = @(Get-MyersOperation -Left $ids.Left -Right $ids.Right)

    $result = [System.Collections.Generic.List[hashtable]]::new()
    $index = 0
    while ($index -lt $ops.Count) {
        $op = $ops[$index]

        if ($op.Kind -ceq 'Same') {
            $result.Add(@{
                    Kind    = 'Same'
                    LeftNo  = $op.LeftIndex + 1
                    RightNo = $op.RightIndex + 1
                    Left    = $BeforeLines[$op.LeftIndex]
                    Right   = $AfterLines[$op.RightIndex]
                })
            $index++
            continue
        }

        # 連続する削除と追加をひとまとまり（塊）として取り出す。
        # Myers の出力は削除が先に並び、その後に追加が並ぶとは限らないため、
        # 塊の中で分類してから対にする
        $deleted = [System.Collections.Generic.List[int]]::new()
        $added = [System.Collections.Generic.List[int]]::new()
        while ($index -lt $ops.Count -and $ops[$index].Kind -cne 'Same') {
            if ($ops[$index].Kind -ceq 'Deleted') { $deleted.Add($ops[$index].LeftIndex) }
            else { $added.Add($ops[$index].RightIndex) }
            $index++
        }

        # 塊の中で、先頭から順に 1 対 1 で突き合わせる。
        # 類似度がしきい値以上なら Changed、未満なら削除と追加のまま残す
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

        # 対にならなかったものを、元の順序を保ったまま並べる。
        # 削除を先に、追加を後に置くのは、diff の慣習（-が先、+が後）に合わせるため
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

        foreach ($entry in ($pending | Sort-Object -CaseSensitive -Property { $_.Order })) {
            $entry.Remove('Order')
            $result.Add($entry)
        }
    }

    return $result.ToArray()
}
