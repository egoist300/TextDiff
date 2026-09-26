#Requires -Version 5.1

function ConvertTo-LineId {
    <#
    .SYNOPSIS
        変更前と変更後の行を、整数 ID に変換する。
    .DESCRIPTION
        同じ内容の行には、変更前と変更後をまたいで同じ ID を割り当てます。
        行の比較は大文字と小文字を区別します。
    .PARAMETER Left
        変更前の行の配列。空の配列と空行を含められます。
    .PARAMETER Right
        変更後の行の配列。空の配列と空行を含められます。
    .OUTPUTS
        [hashtable] @{ Left = [int[]]; Right = [int[]] }
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        # NOTE: AllowEmptyString が必須。Mandatory な [string[]] は、空文字を含む配列を
        #       「引数が空の文字列である」として拒否する。比較する行には空行が含まれる。
        [Parameter(Mandatory)] [AllowEmptyCollection()] [AllowEmptyString()] [string[]]$Left,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [AllowEmptyString()] [string[]]$Right
    )

    # Myers 法は行の一致判定を何度も繰り返す。文字列のまま比較すると、長い行では比較処理が大半の時間を占めるため、先に整数に変換する。
    # 序数比較にするのは、既定の比較子がカルチャに依存し、環境によっては異なる行を同一と判定するため。
    # 大文字と小文字も区別する。データでは大文字と小文字の違いも変更に当たるため。
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
