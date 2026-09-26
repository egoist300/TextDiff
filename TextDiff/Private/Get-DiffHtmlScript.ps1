#Requires -Version 5.1

function Get-DiffHtmlScript {
    <#
    .SYNOPSIS
        左右のペインのスクロール位置を合わせる JavaScript を返す。
    .OUTPUTS
        [string]
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    return @'
// 左右のペインのスクロール位置を合わせる。
// 動かない環境でも各ペインは独立にスクロールできるため、閲覧自体は成立する。
(function () {
  var panes = Array.prototype.slice.call(document.querySelectorAll('.pane'));
  var syncing = false;
  panes.forEach(function (pane) {
    pane.addEventListener('scroll', function () {
      if (syncing) { return; }
      syncing = true;
      panes.forEach(function (other) {
        if (other !== pane) {
          other.scrollLeft = pane.scrollLeft;
          other.scrollTop = pane.scrollTop;
        }
      });
      syncing = false;
    });
  });
})();
'@
}
