#Requires -Version 5.1

function Get-DiffHtmlLegend {
    <#
    .SYNOPSIS
        配色の意味を示す凡例の HTML を返す。
    .OUTPUTS
        [string] 凡例の HTML。
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    # 差分ツールに慣れていない人も HTML を読むため、配色だけで意味が伝わる前提にしない。
    return @'
  <div class="legend">
    <span><i class="d"></i>削除された行</span>
    <span><i class="a"></i>追加された行</span>
    <span><i class="m"></i>行内の変更箇所</span>
    <span><i class="e"></i>反対側に対応する行が無い</span>
    <span><i class="p"></i>右端の帯：差分の位置（左半分は変更前、右半分は変更後。クリックすると、その位置を表示）</span>
  </div>
'@
}
