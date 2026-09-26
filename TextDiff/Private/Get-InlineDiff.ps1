# 書き換えられた 1 行の中で、どこが変わったのかを求める処理。
#
# Get-DiffAlignment が Changed と判定した対にだけ使う。
# 削除と追加が別々の行なら、行の中を比べる意味は無い。
#
# 【なぜ単語（トークン）単位か】
# 文字単位で比べると、桁の変更（varying(100) → varying(20)）のような例では
# 期待どおりに動くが、CSV の 1 行のように長い行では計算量が問題になる。
# Changed と判定される行は「半分以上が共通」なので、共通の先頭・末尾を削っても
# 中央に行の半分（500 文字の行なら 250 文字）が残りうる。
# 250 × 250 の文字比較を変更行の数だけ繰り返すと、実測で 1 行あたり 100 ミリ秒を超える。
#
# 単語単位なら、同じ 250 文字が 40 個程度のトークンに減り、桁が 2 つ落ちる。
# 見た目の粒度も単語単位の方が読みやすく、WinMerge の既定の挙動とも揃う。
#
# 【トークンの切り方】
# 英数字とアンダースコアの連続を 1 トークン、それ以外の文字は 1 文字ずつ 1 トークン。
#   "varying(100)," → "varying" "(" "100" ")" ","
#   "2026-08-17"    → "2026" "-" "08" "-" "17"
# 記号を独立させることで、括弧やハイフンをまたいだ変更をその部分だけ示せる。
# 日本語には英数字の連続が無いため 1 文字ずつになるが、日本語は 1 文字の情報量が
# 大きいので、これで意図どおりの粒度になる。

function Get-InlineDiff {
    <#
    .SYNOPSIS
        書き換えられた 1 行について、変わった部分と変わっていない部分に分ける。
    .DESCRIPTION
        Get-DiffAlignment が Changed と判定した対に対して使います。
        戻り値は左右それぞれの断片列で、連結すると元の行に戻ります。

        処理は 3 段階です。
        1. 共通の先頭・末尾を文字単位で削る。実測で 500 文字の行が 3 文字まで縮み、
           所要時間が 305 ミリ秒から 1 ミリ秒になった。ここが最も効く
        2. 残った中央をトークンに分割し、行の対応づけと同じ Myers 法で比較する
           （比較の実装を 1 つに保つため、専用の実装は書かない）
        3. 隣り合う同じ状態の断片をつなげる

        中央のトークン数が MaxToken を超える場合は、中央をまとめて
        「変わった部分」として返します。行の中がほぼ全面的に違うということなので、
        細かく示しても読めるものにならず、計算時間だけがかかるためです。
    .OUTPUTS
        [hashtable] @{
            Left  = @( @{ Text = '...'; Changed = $false }, ... )
            Right = @( ... )
        }
        断片の Text を順に連結すると、入力の行に一致します。
    .EXAMPLE
        Get-InlineDiff -Left '  name varying(100),' -Right '  name varying(20),'
        # Left  : '  name varying(' / '100'(変更) / '),'
        # Right : '  name varying(' / '20'(変更)  / '),'
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Left,
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Right,
        [ValidateRange(1, [int]::MaxValue)] [int]$MaxToken = 400
    )

    if ($Left -ceq $Right) {
        return @{
            Left  = @(Join-DiffSegment -Segments @(@{ Text = $Left; Changed = $false }))
            Right = @(Join-DiffSegment -Segments @(@{ Text = $Right; Changed = $false }))
        }
    }

    # --- 1. トークンに分けてから、共通の先頭・末尾を削る ---
    #
    # NOTE: 削り込みを文字単位で先に行ってはならない。トークンの途中で切れる。
    #       varying(100), と varying(20), は末尾の "0)," が共通なので、
    #       文字単位で削ると中央が "10" と "2" になり、
    #       強調が「[10]0」「[2]0」という読めない位置に付く（実際にそうなった）。
    #       トークン境界で削れば「[100]」「[20]」になる。
    $allLeft = @(Split-DiffToken -Text $Left)
    $allRight = @(Split-DiffToken -Text $Right)

    $limit = [Math]::Min($allLeft.Count, $allRight.Count)
    $head = 0
    while ($head -lt $limit -and $allLeft[$head] -ceq $allRight[$head]) { $head++ }
    $tail = 0
    while ($tail -lt ($limit - $head) -and
        $allLeft[($allLeft.Count - 1 - $tail)] -ceq $allRight[($allRight.Count - 1 - $tail)]) { $tail++ }

    # NOTE: 範囲の式は条件の中で評価すること。$allLeft[0..($head - 1)] を先に
    #       評価してから上書きする書き方だと、$head = 0 のとき 0..-1 という
    #       範囲になり、空配列に対して配列外参照で落ちる
    #       （before が空＝オブジェクト新規作成時に実際に通る経路）
    $prefix = ''
    if ($head -gt 0) { $prefix = -join $allLeft[0..($head - 1)] }
    $suffix = ''
    if ($tail -gt 0) { $suffix = -join $allLeft[($allLeft.Count - $tail)..($allLeft.Count - 1)] }

    $leftTokens = @()
    if (($allLeft.Count - $head - $tail) -gt 0) { $leftTokens = @($allLeft[$head..($allLeft.Count - 1 - $tail)]) }
    $rightTokens = @()
    if (($allRight.Count - $head - $tail) -gt 0) { $rightTokens = @($allRight[$head..($allRight.Count - 1 - $tail)]) }

    $leftSegments = [System.Collections.Generic.List[hashtable]]::new()
    $rightSegments = [System.Collections.Generic.List[hashtable]]::new()
    $leftSegments.Add(@{ Text = $prefix; Changed = $false })
    $rightSegments.Add(@{ Text = $prefix; Changed = $false })

    # --- 2. 残った中央を Myers 法で比較する ---
    if ($leftTokens.Count -gt $MaxToken -or $rightTokens.Count -gt $MaxToken) {
        # 上限超え: 中央をまとめて変更扱いにする
        $leftSegments.Add(@{ Text = (-join $leftTokens); Changed = $true })
        $rightSegments.Add(@{ Text = (-join $rightTokens); Changed = $true })
    }
    else {
        $ids = ConvertTo-LineId -Left $leftTokens -Right $rightTokens
        # NOTE: @() で囲むこと。空のリストが返ると PowerShell が $null に展開し、
        #       StrictMode 下で直後の列挙が落ちる（Get-DiffAlignment と同じ理由）
        $ops = @(Get-MyersOperation -Left $ids.Left -Right $ids.Right)

        foreach ($op in $ops) {
            switch -CaseSensitive ($op.Kind) {
                'Same' {
                    $leftSegments.Add(@{ Text = $leftTokens[$op.LeftIndex]; Changed = $false })
                    $rightSegments.Add(@{ Text = $rightTokens[$op.RightIndex]; Changed = $false })
                }
                'Deleted' { $leftSegments.Add(@{ Text = $leftTokens[$op.LeftIndex]; Changed = $true }) }
                'Added' { $rightSegments.Add(@{ Text = $rightTokens[$op.RightIndex]; Changed = $true }) }
            }
        }
    }

    $leftSegments.Add(@{ Text = $suffix; Changed = $false })
    $rightSegments.Add(@{ Text = $suffix; Changed = $false })

    # --- 3. 隣り合う同じ状態をつなげる ---
    return @{
        Left  = @(Join-DiffSegment -Segments $leftSegments.ToArray())
        Right = @(Join-DiffSegment -Segments $rightSegments.ToArray())
    }
}
