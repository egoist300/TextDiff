#Requires -Version 5.1

function Get-DiffHtmlPane {
    <#
    .SYNOPSIS
        変更前または変更後のペインの HTML を生成する。
    .DESCRIPTION
        反対側にしか無い行の位置には空行を配置し、斜線で対応する行が無いことを示します。
    .PARAMETER Rows
        Get-DiffAlignment が返す行の対応付け（TextDiff.DiffRow の配列）。それ以外は受け付けません。
    .PARAMETER InlineDiffs
        変更行（Kind が Changed の行）の行内の差分。キーは Rows の添字、値は Get-InlineDiff の戻り値です。
        すべての変更行について指定します。指定が無い変更行があると、ArgumentException で失敗します。
    .PARAMETER Side
        生成する側。'left' は変更前、'right' は変更後です。
    .OUTPUTS
        [string] ペインの HTML。
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [PSTypeName('TextDiff.DiffRow')] [psobject[]]$Rows,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [System.Collections.Generic.Dictionary[int, hashtable]]$InlineDiffs,
        [Parameter(Mandatory)] [ValidateSet('left', 'right', IgnoreCase = $false)] [string]$Side
    )

    $builder = [System.Text.StringBuilder]::new()
    [void]$builder.AppendLine("    <div class=""pane $Side"">")
    [void]$builder.AppendLine('      <table>')

    for ($rowIndex = 0; $rowIndex -lt $Rows.Count; $rowIndex++) {
        $row = $Rows[$rowIndex]
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
            # 反対側にしか無い行も空行を配置し、左右の行数を一致させる。一致しないと行が上下にずれ、左右を比較できない。
            [void]$builder.AppendLine("        <tr$rowClass><td class=""ln""></td><td class=""tx empty""></td></tr>")
            continue
        }

        if ($row.Kind -ceq 'Changed') {
            if (-not $InlineDiffs.ContainsKey($rowIndex)) {
                throw [System.ArgumentException]::new(("InlineDiffs に変更行の行内の差分がありません（Rows の添字: {0}）" -f $rowIndex), 'InlineDiffs')
            }
            $inline = $InlineDiffs[$rowIndex]
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
