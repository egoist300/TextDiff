#Requires -Version 5.1

function Join-DiffSegment {
    <#
    .SYNOPSIS
        隣接する同じ状態の断片を結合し、TextDiff.Segment に変換する。
    .DESCRIPTION
        空文字の断片は除外します。
    .PARAMETER Segments
        @{ Text; Changed } の配列。Get-InlineDiff がトークン単位で作成したもの。
    .OUTPUTS
        TextDiff.Segment。[PSCustomObject]@{ Text; Changed } の配列。
    #>
    [CmdletBinding()]
    [OutputType('TextDiff.Segment')]
    param(
        # 入力はハッシュテーブルのまま受け取る。Get-InlineDiff がトークンの数だけ作成するもので、利用者には渡らないため。
        [Parameter(Mandatory)] [AllowEmptyCollection()] [hashtable[]]$Segments
    )

    # 結合しないと、共通部分がトークンの数だけの細かい断片になる。表示側は断片ごとに色を切り替えるため、
    # コンソールでは Write-Host の呼び出し回数が増えて遅くなる（1 回あたり約 0.6 ミリ秒）。
    $merged = [System.Collections.Generic.List[object]]::new()
    foreach ($segment in $Segments) {
        if ($segment.Text.Length -eq 0) { continue }
        if ($merged.Count -gt 0 -and $merged[($merged.Count - 1)].Changed -ceq $segment.Changed) {
            $merged[($merged.Count - 1)].Text += $segment.Text
        }
        else {
            $merged.Add([PSCustomObject]@{ PSTypeName = 'TextDiff.Segment'; Text = $segment.Text; Changed = $segment.Changed })
        }
    }
    return $merged.ToArray()
}
