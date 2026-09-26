function ConvertTo-HtmlSegment {
    <#
    .SYNOPSIS
        断片の並びを、行内強調つきの HTML 断片へ変換する。
    .DESCRIPTION
        エスケープしてから強調のタグで包みます。順序を逆にすると、
        タグ自体がエスケープされて &lt;b&gt; と表示されます。
    .PARAMETER Segments
        Get-InlineDiff が返す片側の断片（@{ Text; Changed } の配列）。$null なら空文字を返します。
    .OUTPUTS
        [string]
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()] [AllowEmptyCollection()] $Segments
    )

    if ($null -eq $Segments) { return '' }
    $builder = [System.Text.StringBuilder]::new()
    foreach ($segment in @($Segments)) {
        $escaped = ConvertTo-HtmlText -Text $segment.Text
        if ($segment.Changed) { [void]$builder.Append("<b>$escaped</b>") }
        else { [void]$builder.Append($escaped) }
    }
    return $builder.ToString()
}
