#Requires -Version 5.1

function ConvertTo-HtmlSegment {
    <#
    .SYNOPSIS
        断片の配列を、変更箇所を強調した HTML 文字列に変換する。
    .DESCRIPTION
        Changed が $true の断片を <b> タグで囲みます。
    .PARAMETER Segments
        Get-InlineDiff が返す片側の断片（TextDiff.Segment の配列）。$null なら空文字を返します。
    .OUTPUTS
        [string] HTML 文字列。
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()] [AllowEmptyCollection()] $Segments
    )

    if ($null -eq $Segments) { return '' }
    $builder = [System.Text.StringBuilder]::new()
    foreach ($segment in @($Segments)) {
        # エスケープしてからタグで囲む。逆の順序では、タグ自体がエスケープされて &lt;b&gt; と表示される。
        $escaped = ConvertTo-HtmlText -Text $segment.Text
        if ($segment.Changed) { [void]$builder.Append("<b>$escaped</b>") }
        else { [void]$builder.Append($escaped) }
    }
    return $builder.ToString()
}
