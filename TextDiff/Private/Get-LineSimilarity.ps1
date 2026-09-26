#Requires -Version 5.1

function Get-LineSimilarity {
    <#
    .SYNOPSIS
        2 行の類似度を 0.0〜1.0 で返す。
    .DESCRIPTION
        削除行と追加行を、1 行の変更（Changed）として対応付けるかの判定に使います。
        類似度は「共通の先頭・末尾の文字数 ÷ 長い方の行の文字数」で計算します。
    .PARAMETER Left
        比較する一方の行。空文字も受け取ります。
    .PARAMETER Right
        比較するもう一方の行。空文字も受け取ります。両方が空なら 1.0 を返します。
    .OUTPUTS
        [double] 0.0（共通する先頭・末尾なし）〜 1.0（完全一致）
    #>
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Left,
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Right
    )

    $longer = [Math]::Max($Left.Length, $Right.Length)
    if ($longer -eq 0) { return 1.0 }

    # LCS（最長共通部分列）を使わないのは、対応付けの判定のためだけに計算すると、判定の処理時間が差分計算の本体を上回るため。
    # 対応付けたい変更（桁数・日付・コード値の変更）は先頭と末尾が共通で、中央だけが異なるので、この近似で十分。
    # 列自体が別の列に置換された場合は共通部分が短く、類似度は低くなる。
    $limit = [Math]::Min($Left.Length, $Right.Length)
    $head = 0
    while ($head -lt $limit -and $Left[$head] -ceq $Right[$head]) { $head++ }
    $tail = 0
    while ($tail -lt ($limit - $head) -and
        $Left[($Left.Length - 1 - $tail)] -ceq $Right[($Right.Length - 1 - $tail)]) { $tail++ }

    return [double]($head + $tail) / $longer
}
