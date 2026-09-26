#Requires -Version 5.1

function ConvertTo-LineId {
    <#
    .SYNOPSIS
        before/after の行を整数IDに置き換える。
    .DESCRIPTION
        Myers 法の内側のループは行の一致判定を何度も繰り返します。
        文字列のまま比較すると、1 行が数百文字ある CSV では比較そのものが
        支配的なコストになるため、先に同じ内容の行へ同じ整数を割り当てます。

        比較は大小文字を区別します（PostgreSQL の識別子は小文字に畳み込まれますが、
        データやクォート識別子では大小文字が意味を持つため）。
    .PARAMETER Left
        before の行の並び。空の配列と空行を含められます。
    .PARAMETER Right
        after の行の並び。空の配列と空行を含められます。Left と同じ内容の行には同じ ID を振ります。
    .OUTPUTS
        [hashtable] @{ Left = [int[]]; Right = [int[]] }
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        # NOTE: AllowEmptyString が必須。Mandatory な [string[]] は、空文字を含む配列を
        #       「引数が空の文字列である」として拒否する。pg_dump の出力には空行が含まれるため、
        #       これが無いとテーブル定義のスナップショットで必ず落ちる（実際に落ちた）
        [Parameter(Mandatory)] [AllowEmptyCollection()] [AllowEmptyString()] [string[]]$Left,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [AllowEmptyString()] [string[]]$Right
    )

    # 序数比較。既定の比較子はカルチャ依存で、環境によって別の行が同一と判定されうる
    $map = New-Object -TypeName 'System.Collections.Generic.Dictionary[string,int]' -ArgumentList ([System.StringComparer]::Ordinal)
    $leftIds = New-Object -TypeName 'int[]' -ArgumentList $Left.Length
    $rightIds = New-Object -TypeName 'int[]' -ArgumentList $Right.Length

    for ($leftIndex = 0; $leftIndex -lt $Left.Length; $leftIndex++) {
        if (-not $map.ContainsKey($Left[$leftIndex])) { $map[$Left[$leftIndex]] = $map.Count }
        $leftIds[$leftIndex] = $map[$Left[$leftIndex]]
    }
    for ($rightIndex = 0; $rightIndex -lt $Right.Length; $rightIndex++) {
        if (-not $map.ContainsKey($Right[$rightIndex])) { $map[$Right[$rightIndex]] = $map.Count }
        $rightIds[$rightIndex] = $map[$Right[$rightIndex]]
    }
    return @{ Left = $leftIds; Right = $rightIds }
}
