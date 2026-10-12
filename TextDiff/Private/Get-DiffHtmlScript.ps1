#Requires -Version 5.1

function Get-DiffHtmlScript {
    <#
    .SYNOPSIS
        左右のペインのスクロール位置の同期と、差分マップのクリックによる移動を行う JavaScript を返す。
    .OUTPUTS
        [string]
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    return @'
// 左右のペインのスクロール位置を同期する。
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

// 差分マップをクリックすると、その位置の行をペインの中央に表示する。
// 印の位置は行の位置に比例するため、クリックした高さの割合をスクロール量に換算する。
// 動かない環境でも印は表示されるため、差分の位置は分かる。
(function () {
  Array.prototype.forEach.call(document.querySelectorAll('.map'), function (map) {
    var pane = map.parentNode.querySelector('.pane');
    map.addEventListener('click', function (event) {
      var ratio = (event.clientY - map.getBoundingClientRect().top) / map.clientHeight;
      pane.scrollTop = ratio * pane.scrollHeight - pane.clientHeight / 2;
    });
  });
})();
'@
}
