#Requires -Version 5.1

function Get-DiffHtmlPane {
    <#
    .SYNOPSIS
        変更前または変更後のペインの HTML を生成する。
    .DESCRIPTION
        反対側にしか無い行の位置には空行を置き、斜線で対応する行が無いことを示します。
    .PARAMETER Rows
        Get-DiffAlignment が返す行の対応付け（TextDiff.DiffRow の配列）。それ以外は受け付けません。
    .PARAMETER Side
        生成する側。'left' は変更前、'right' は変更後です。
    .OUTPUTS
        [string] ペインの HTML。
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
            # 反対側にしか無い行も空行を置き、左右の行数を揃える。揃えないと行が上下にずれ、左右を比較できない。
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
