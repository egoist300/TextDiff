#Requires -Version 5.1

function Join-DiffSegment {
    <#
    .SYNOPSIS
        隣り合う同じ状態の断片をつなげ、利用者に返す断片（TextDiff.Segment）にする。
    .DESCRIPTION
        トークン単位の結果をそのまま渡すと、変わっていない部分が
        トークンの数だけ細切れの断片になります。描画側が断片ごとに
        色を切り替えることになり、コンソールでは Write-Host の回数が
        跳ね上がって遅くなります（1 回あたり約 0.6 ミリ秒）。

        入力はハッシュテーブルのまま受け取ります。Get-InlineDiff の中で
        トークンの数だけ作るもので、利用者には見えないためです。
    .PARAMETER Segments
        @{ Text; Changed } の配列。Get-InlineDiff がトークン単位で組み立てたもの。
    .OUTPUTS
        TextDiff.Segment。[PSCustomObject]@{ Text; Changed } の配列で、空文字の断片は含まない。
    #>
    [CmdletBinding()]
    [OutputType('TextDiff.Segment')]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [hashtable[]]$Segments
    )

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
