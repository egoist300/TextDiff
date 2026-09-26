function Get-DiffHtmlPane {
    <#
    .SYNOPSIS
        片側（before または after）のペインを組み立てる。
    .DESCRIPTION
        左右のペインは同じ行数になります。反対側にしか無い行の位置には
        空の行を置き、斜線で「対応する行が無い」ことを示します。
        行数を揃えないと、行が上下にずれて左右の比較が成立しません。
    .PARAMETER Rows
        Get-DiffAlignment が返す行の対応づけ（TextDiff.DiffRow の配列）。それ以外は受け付けません。
    .PARAMETER Side
        組み立てる側。'left' なら before、'right' なら after の行を並べます。
    .OUTPUTS
        [string]
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [PSTypeName('TextDiff.DiffRow')] [psobject[]]$Rows,
        [Parameter(Mandatory)] [ValidateSet('left', 'right', IgnoreCase = $false)] [string]$Side
    )

    $builder = [System.Text.StringBuilder]::new()
    [void]$builder.AppendLine("    <div class=""pane $Side"">")
    [void]$builder.AppendLine('      <table>')

    foreach ($row in $Rows) {
        $isLeft = ($Side -ceq 'left')
        $number = if ($isLeft) { $row.LeftNo } else { $row.RightNo }
        $text = if ($isLeft) { $row.Left } else { $row.Right }

        $rowClass = switch -CaseSensitive ($row.Kind) {
            'Changed' { ' class="mod"' }
            'Deleted' { ' class="del"' }
            'Added' { ' class="add"' }
            default { '' }
        }

        if ($null -eq $number) {
            # 反対側にしか無い行。斜線を出す
            [void]$builder.AppendLine("        <tr$rowClass><td class=""ln""></td><td class=""tx empty""></td></tr>")
            continue
        }

        if ($row.Kind -ceq 'Changed') {
            $inline = Get-InlineDiff -Left $row.Left -Right $row.Right
            $body = ConvertTo-HtmlSegment -Segments $(if ($isLeft) { $inline.Left } else { $inline.Right })
        }
        else {
            $body = ConvertTo-HtmlText -Text ([string]$text)
        }
        [void]$builder.AppendLine("        <tr$rowClass><td class=""ln"">$number</td><td class=""tx"">$body</td></tr>")
    }

    [void]$builder.AppendLine('      </table>')
    [void]$builder.Append('    </div>')
    return $builder.ToString()
}
