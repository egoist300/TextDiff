function Join-DiffSegment {
    <#
    .SYNOPSIS
        隣り合う同じ状態の断片をつなげる。
    .DESCRIPTION
        トークン単位の結果をそのまま渡すと、変わっていない部分が
        トークンの数だけ細切れの断片になります。描画側が断片ごとに
        色を切り替えることになり、コンソールでは Write-Host の回数が
        跳ね上がって遅くなります（1 回あたり約 0.6 ミリ秒）。
    .PARAMETER Segments
        @{ Text; Changed } の配列。Get-InlineDiff がトークン単位で組み立てたもの。
    .OUTPUTS
        [hashtable[]] つなげた後の断片。
    #>
    [CmdletBinding()]
    [OutputType([hashtable[]])]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [array]$Segments
    )

    $merged = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($segment in $Segments) {
        if ($segment.Text.Length -eq 0) { continue }
        if ($merged.Count -gt 0 -and $merged[($merged.Count - 1)].Changed -ceq $segment.Changed) {
            $merged[($merged.Count - 1)].Text += $segment.Text
        }
        else {
            $merged.Add(@{ Text = $segment.Text; Changed = $segment.Changed })
        }
    }
    return $merged.ToArray()
}
