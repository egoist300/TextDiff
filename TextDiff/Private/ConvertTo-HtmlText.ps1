#Requires -Version 5.1

function ConvertTo-HtmlText {
    <#
    .SYNOPSIS
        HTML に埋め込む文字列をエスケープする。
    .DESCRIPTION
        & < > " を文字参照に置換します。
    .PARAMETER Text
        HTML に埋め込む文字列。空文字も受け取ります。
    .OUTPUTS
        [string] エスケープした文字列。
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Text
    )

    # & を最初に置換する。後にすると、他の置換で生成した & を二重にエスケープする。
    return $Text.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;')
}
