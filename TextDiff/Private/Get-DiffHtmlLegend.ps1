#Requires -Version 5.1

function Get-DiffHtmlLegend {
    <#
    .SYNOPSIS
        色の意味を示す凡例を返す。
    .DESCRIPTION
        WinMerge には無いものですが、証跡は差分ツールに慣れていない人も読みます。
        色だけで意味を察してもらう前提にしないために付けています。
    .OUTPUTS
        [string]
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    return @'
  <div class="legend">
    <span><i class="d"></i>削除された行</span>
    <span><i class="a"></i>追加された行</span>
    <span><i class="m"></i>行内で変わった部分</span>
    <span><i class="e"></i>反対側に対応する行が無い</span>
  </div>
'@
}
