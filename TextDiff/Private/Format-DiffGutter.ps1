#Requires -Version 5.1

function Format-DiffGutter {
    <#
    .SYNOPSIS
        行番号とマーカーから、桁数を統一した見出しを作成する。
    .PARAMETER Number
        行番号。反対側にしか無い行では省略し、その桁を空白で埋めます。
    .PARAMETER Marker
        '-'（削除行）、'+'（追加行）、' '（共通行）のいずれか。
    .PARAMETER Width
        行番号の桁数。これより長い行番号は切り詰めません。
    .OUTPUTS
        [string] 見出し。
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Nullable[int]]$Number,
        [Parameter(Mandatory)] [ValidateSet('-', '+', ' ', IgnoreCase = $false)] [string]$Marker,
        [Parameter(Mandatory)] [ValidateRange(1, 100)] [int]$Width
    )

    $text = if ($null -ne $Number) { ([string]$Number).PadLeft($Width) } else { ' ' * $Width }
    return "  $text$Marker "
}
