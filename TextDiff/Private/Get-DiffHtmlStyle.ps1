function Get-DiffHtmlStyle {
    <#
    .SYNOPSIS
        埋め込む CSS を返す。
    .DESCRIPTION
        配色はコンソールと同じ考え方に揃えています。
        削除はマゼンタ（赤にしない。削除は正常な結果であり、失敗と混同させない）、
        追加は緑、行内で変わった部分はオレンジ。
        ダークモードでも読めるよう、配色を二組用意しています。
    .OUTPUTS
        [string]
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    return @'
  :root {
    --ground: #f6f8fa; --surface: #ffffff; --surface-alt: #eef2f6;
    --ink: #161c22; --ink-soft: #55636f; --rule: #d3dce4; --structure: #0e6f86;
    --del-ink: #8e2069; --del-bg: #fbeaf4;
    --add-ink: #14733c; --add-bg: #e8f5ec;
    --mod-bg: #ffd9a8; --mod-ink: #7a3d00;
    --warn-ink: #8a1f1f; --warn-bg: #fdeaea;
    --gutter: #f0f3f6; --code-ink: #1c242c;
  }
  @media (prefers-color-scheme: dark) {
    :root:not([data-theme="light"]) {
      --ground: #0d1116; --surface: #151b22; --surface-alt: #1c242d;
      --ink: #e4ebf1; --ink-soft: #93a2b0; --rule: #2b353f; --structure: #4bb8d4;
      --del-ink: #f19ad0; --del-bg: #2e1626;
      --add-ink: #7fd6a0; --add-bg: #12261a;
      --mod-bg: #8a5200; --mod-ink: #ffe8c9;
      --warn-ink: #ff9d9d; --warn-bg: #2c1414;
      --gutter: #10161c; --code-ink: #dce5ed;
    }
  }
  * { box-sizing: border-box; }
  body { margin: 0; background: var(--ground); color: var(--ink);
         font-family: "Yu Gothic UI", "Meiryo", "Segoe UI", system-ui, sans-serif; }
  .wrap { max-width: 1400px; margin: 0 auto; padding: 28px 20px 64px; }
  h1 { font-size: 19px; margin: 0 0 20px; }
  .card { background: var(--surface); border: 1px solid var(--rule); border-radius: 5px;
          overflow: hidden; margin-bottom: 22px; }
  .card-head { padding: 10px 14px; border-bottom: 1px solid var(--rule);
               background: var(--surface-alt); font-size: 14px; font-weight: 700; }
  .side { display: flex; font-size: 12px; color: var(--ink-soft);
          border-bottom: 1px solid var(--rule); background: var(--surface-alt); }
  .side div { width: 50%; padding: 5px 14px; }
  .side div + div { border-left: 1px solid var(--rule); }
  .panes { display: flex; }
  .pane { width: 50%; overflow: auto; max-height: 70vh; }
  .pane + .pane { border-left: 1px solid var(--rule); }
  table { border-collapse: collapse; width: 100%;
          font-family: "Cascadia Code", "Consolas", monospace; font-size: 12.5px;
          line-height: 1.6; color: var(--code-ink); }
  td { padding: 1px 0; vertical-align: top; white-space: pre; height: 1.6em; }
  .ln { width: 3.4em; min-width: 3.4em; padding: 1px 8px 1px 0 !important; text-align: right;
        color: var(--ink-soft); background: var(--gutter); user-select: none;
        border-right: 1px solid var(--rule); position: sticky; left: 0; }
  .tx { padding: 1px 14px 1px 8px !important; }
  tr.del .tx { background: var(--del-bg); color: var(--del-ink); }
  tr.mod .tx { background: var(--del-bg); color: var(--del-ink); }
  .pane.right tr.add .tx { background: var(--add-bg); color: var(--add-ink); }
  .pane.right tr.mod .tx { background: var(--add-bg); color: var(--add-ink); }
  .tx b { background: var(--mod-bg); color: var(--mod-ink); font-weight: 700;
          border-radius: 2px; padding: 0 1px; }
  td.empty { background: repeating-linear-gradient(135deg, transparent, transparent 5px,
             var(--gutter) 5px, var(--gutter) 10px); }
  .nodiff { padding: 14px; color: var(--ink-soft); font-size: 13px; }
  .unverified { padding: 12px 14px; background: var(--warn-bg); color: var(--warn-ink);
                font-family: "Cascadia Code", "Consolas", monospace; font-size: 12.5px;
                white-space: pre-wrap; }
  .legend { display: flex; flex-wrap: wrap; gap: 18px; padding: 9px 14px;
            border-top: 1px solid var(--rule); font-size: 12.5px; color: var(--ink-soft); }
  .legend i { display: inline-block; width: 11px; height: 11px; border-radius: 2px;
              margin-right: 6px; vertical-align: -1px; }
  .legend .d { background: var(--del-bg); border: 1px solid var(--del-ink); }
  .legend .a { background: var(--add-bg); border: 1px solid var(--add-ink); }
  .legend .m { background: var(--mod-bg); border: 1px solid var(--mod-ink); }
  .legend .e { background: var(--gutter); border: 1px solid var(--rule); }
'@
}
