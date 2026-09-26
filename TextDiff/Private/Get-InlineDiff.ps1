#Requires -Version 5.1

function Get-InlineDiff {
    <#
    .SYNOPSIS
        変更があった 1 行を、変更箇所と共通部分の断片に分割する。
    .DESCRIPTION
        Get-DiffAlignment が Changed と判定した行について、変更前後の行を比較します。
        削除行と追加行が別の行なら、行内を比較しない。
        変更箇所のトークン数が MaxToken を超える場合は、詳細に比較せず、変更箇所全体を 1 つの変更として返す。
        行の大部分が異なるので、詳細に示しても読めず、計算時間がかかるためです。
    .PARAMETER Left
        変更前の行。空文字も受け取ります。
    .PARAMETER Right
        変更後の行。空文字も受け取ります。
    .PARAMETER MaxToken
        変更箇所を詳細に比較するトークン数の上限。
    .OUTPUTS
        [hashtable] @{
            Left  = @( TextDiff.Segment, ... )
            Right = @( TextDiff.Segment, ... )
        }
        それぞれの断片の Text を順に連結すると、入力の行に一致します。
        外側の組はモジュール内部でのみ使うため、ハッシュテーブルのままにしています。
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

    # --- 1. トークンに分割し、共通の先頭・末尾を除去する ---
    # トークン単位で分割する理由は、文字単位では長い行の比較に 1 行あたり 100 ミリ秒以上かかるため。
    # 先に共通の先頭・末尾を除去する理由は、MaxToken を変更箇所だけで判定するため。
    # 文字単位で除去すると、varying(100) と varying(20) の強調が「[10]0」「[2]0」とトークンの途中で切れる
    $allLeft = @(Split-DiffToken -Text $Left)
    $allRight = @(Split-DiffToken -Text $Right)

    $limit = [Math]::Min($allLeft.Count, $allRight.Count)
    $head = 0
    while ($head -lt $limit -and $allLeft[$head] -ceq $allRight[$head]) { $head++ }
    $tail = 0
    while ($tail -lt ($limit - $head) -and
        $allLeft[($allLeft.Count - 1 - $tail)] -ceq $allRight[($allRight.Count - 1 - $tail)]) { $tail++ }

    $leftList = [System.Collections.Generic.List[string]]::new([string[]]$allLeft)
    $rightList = [System.Collections.Generic.List[string]]::new([string[]]$allRight)
    $prefix = -join $leftList.GetRange(0, $head)
    $suffix = -join $leftList.GetRange($leftList.Count - $tail, $tail)
    $leftTokens = @($leftList.GetRange($head, $leftList.Count - $head - $tail))
    $rightTokens = @($rightList.GetRange($head, $rightList.Count - $head - $tail))

    $leftSegments = [System.Collections.Generic.List[hashtable]]::new()
    $rightSegments = [System.Collections.Generic.List[hashtable]]::new()
    $leftSegments.Add(@{ Text = $prefix; Changed = $false })
    $rightSegments.Add(@{ Text = $prefix; Changed = $false })

    # --- 2. 残りの変更箇所を Myers 法で比較する ---
    if ($leftTokens.Count -gt $MaxToken -or $rightTokens.Count -gt $MaxToken) {
        $leftSegments.Add(@{ Text = (-join $leftTokens); Changed = $true })
        $rightSegments.Add(@{ Text = (-join $rightTokens); Changed = $true })
    }
    else {
        $ids = ConvertTo-LineId -Left $leftTokens -Right $rightTokens
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

    # --- 3. 隣接する同じ状態の断片を結合する ---
    return @{
        Left  = @(Join-DiffSegment -Segments $leftSegments.ToArray())
        Right = @(Join-DiffSegment -Segments $rightSegments.ToArray())
    }
}
