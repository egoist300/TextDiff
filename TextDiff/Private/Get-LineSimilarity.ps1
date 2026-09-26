#Requires -Version 5.1

function Get-LineSimilarity {
    <#
    .SYNOPSIS
        2 行がどれだけ似ているかを 0.0〜1.0 で返す。
    .DESCRIPTION
        削除と追加を「1 行の書き換え」として対にしてよいかの判断に使います。
        判定は「共通の先頭・末尾の文字数 ÷ 長い方の文字数」です。
        文字単位の LCS を使わないのは、対にするかどうかを決めるだけのために
        全組み合わせへ LCS をかけると、判定のコストが本体を上回るためです。

        この近似で足りるのは、実際に対にしたい変更（桁の変更・日付の変更・
        コードの変更）が、行の前後を共有したまま中央だけ differ するからです。
        逆に列そのものが差し替わった場合は共通部分が短く、自然に低い値になります。
    .PARAMETER Left
        比べる一方の行。空文字も受け取ります。
    .PARAMETER Right
        比べるもう一方の行。空文字も受け取ります。両方が空なら 1.0 を返します。
    .OUTPUTS
        [double] 0.0（全く似ていない）〜 1.0（完全一致）
    #>
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Left,
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Right
    )

    $longer = [Math]::Max($Left.Length, $Right.Length)
    if ($longer -eq 0) { return 1.0 }

    $limit = [Math]::Min($Left.Length, $Right.Length)
    $head = 0
    while ($head -lt $limit -and $Left[$head] -ceq $Right[$head]) { $head++ }
    $tail = 0
    while ($tail -lt ($limit - $head) -and
        $Left[($Left.Length - 1 - $tail)] -ceq $Right[($Right.Length - 1 - $tail)]) { $tail++ }

    return [double]($head + $tail) / $longer
}
