function ConvertTo-HtmlText {
    <#
    .SYNOPSIS
        HTML に埋め込む文字列をエスケープする。
    .DESCRIPTION
        スナップショットにはテーブル定義やデータがそのまま入ります。
        COMMENT や文字列型のデータに < > & が含まれることは普通にあり、
        エスケープを忘れると表示が壊れるだけでなく、意図しないタグとして
        解釈されて内容が消えます。証跡が黙って欠けるので、体裁ではなく
        正しさの問題として扱います。

        & を最初に置き換えること。後にすると、他の置換で作った & を
        二重にエスケープしてしまいます。
    .PARAMETER Text
        HTML に埋め込む文字列。空文字も受け取ります。
    .OUTPUTS
        [string]
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Text
    )

    return $Text.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;')
}
