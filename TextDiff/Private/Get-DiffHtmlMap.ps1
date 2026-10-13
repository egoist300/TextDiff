#Requires -Version 5.1

function Get-DiffHtmlMap {
    <#
    .SYNOPSIS
        差分の位置を示す差分マップの HTML を生成する。
    .DESCRIPTION
        ペインと同じ高さの縦の帯を左右 2 列に分割し、左の列に削除・変更された行（変更前の差分）、
        右の列に追加・変更された行（変更後の差分）の位置を印で示します。
        各列で連続する行は 1 つの印にまとめます。印の位置と高さは、全体の行数に対する割合で指定します。
    .PARAMETER Rows
        Get-DiffAlignment が返す行の対応付け（TextDiff.DiffRow の配列）。それ以外は受け付けません。
    .OUTPUTS
        [string] 差分マップの HTML。
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [PSTypeName('TextDiff.DiffRow')] [psobject[]]$Rows
    )

    $builder = [System.Text.StringBuilder]::new()
    [void]$builder.AppendLine('    <div class="map" title="差分の位置。クリックすると、その位置を表示します">')

    # 列の並びを左右のペインと揃え、変更前と変更後のどちらの差分かを位置で区別できるようにする。
    $lanes = @(
        @{ MarkerClass = 'd'; Kinds = @('Deleted', 'Changed') },
        @{ MarkerClass = 'a'; Kinds = @('Added', 'Changed') }
    )
    foreach ($lane in $lanes) {
        $index = 0
        while ($index -lt $Rows.Count) {
            if ($lane.Kinds -cnotcontains $Rows[$index].Kind) {
                $index++
                continue
            }
            $start = $index
            while ($index -lt $Rows.Count -and $lane.Kinds -ccontains $Rows[$index].Kind) { $index++ }

            # 小数点をカンマにするカルチャーでは CSS として解釈されないため、InvariantCulture で書式化する。
            $style = [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, 'top: {0:0.###}%; height: {1:0.###}%',
                ($start * 100.0 / $Rows.Count), (($index - $start) * 100.0 / $Rows.Count))
            [void]$builder.AppendLine(("      <i class=""{0}"" style=""{1}""></i>" -f $lane.MarkerClass, $style))
        }
    }

    [void]$builder.Append('    </div>')
    return $builder.ToString()
}
