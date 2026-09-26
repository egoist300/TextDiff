# 変更履歴

版の上げ方は [`CLAUDE.md`](CLAUDE.md) の「Versioning」にあります。
PowerShell Gallery に一度公開した版は上書きできないため、公開する前にここへ書きます。

## 1.0.0 - 2026-09-26

最初の公開版です。

- `Get-DiffAlignment`: 2 つの行の並びを Myers 法で対応づけ、行ごとに Same / Changed / Deleted / Added を返す。
  隣り合った削除と追加は、類似度がしきい値以上のときだけ同じ行の書き換え（Changed）として対にする
- `ConvertTo-DiffText`: 対応づけの結果を、コンソール表示用の行（行番号と、行内で変わった部分を分けた断片）に変換する。
  変更から離れた行は、畳んだ行数（`OmittedCount`）だけを返す
- `ConvertTo-DiffHtml`: 対応づけの結果を、左右に並べた 1 ファイル完結の HTML に変換する
