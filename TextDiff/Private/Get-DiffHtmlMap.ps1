#Requires -Version 5.1

function Get-DiffHtmlMap {
    <#
    .SYNOPSIS
        差分の位置を示す差分マップの HTML を生成する。
    .DESCRIPTION
        ペインと同じ高さの縦の帯に、変更・削除・追加された行の位置を印で示します。
        連続する同じ種類の行は 1 つの印にまとめます。印の位置と高さは、全体の行数に対する割合で指定します。
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

    $index = 0
    while ($index -lt $Rows.Count) {
        $kind = $Rows[$index].Kind
        $start = $index
        while ($index -lt $Rows.Count -and $Rows[$index].Kind -ceq $kind) { $index++ }
        if ($kind -ceq 'Same') { continue }

        $markerClass = switch -CaseSensitive ($kind) {
            'Changed' { 'm' }
            'Deleted' { 'd' }
            'Added' { 'a' }
        }
        # 小数点をカンマにするカルチャーでは CSS として解釈されないため、InvariantCulture で書式化する。
        $style = [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, 'top: {0:0.###}%; height: {1:0.###}%',
            ($start * 100.0 / $Rows.Count), (($index - $start) * 100.0 / $Rows.Count))
        [void]$builder.AppendLine("      <i class=""$markerClass"" style=""$style""></i>")
    }

    [void]$builder.Append('    </div>')
    return $builder.ToString()
}
