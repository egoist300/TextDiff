# TextDiff

2 つの行の並び（変更前と変更後）の差分を求め、コンソール表示用の行と、左右に並べた HTML に変換する PowerShell モジュールです。

- 行の対応づけに Myers 法を使います。変更が少ないほど速く、1000 行のうち 5 行が変わった場合で約 14 ミリ秒でした（Windows PowerShell 5.1 での実測）
- 隣り合った削除と追加は、似ている行だけを「同じ行の書き換え」として対にし、行内で変わった部分（単語単位）まで求めます
- HTML は CSS と JavaScript を埋め込んだ 1 ファイルで、外部から何も読み込みません。別のマシンにコピーしても表示が崩れません

出力の見出し・凡例などの文言は日本語です。

## 動作環境

Windows PowerShell 5.1。

## インストール

```powershell
Install-Module -Name TextDiff -Scope CurrentUser -RequiredVersion 1.0.0
```

`C:\Users\<ユーザー名>\Documents\WindowsPowerShell\Modules\TextDiff\1.0.0\` に入ります。

インターネットにつながらない環境で使うときは、つながる環境で保存してから、フォルダごと持ち込みます。

```powershell
Save-Module -Name TextDiff -RequiredVersion 1.0.0 -Path .\Modules
# 持ち込んだ先で
Import-Module -Name .\Modules\TextDiff\1.0.0\TextDiff.psd1
```

## 使い方

### 行を対応づける

```powershell
$rows = Get-DiffAlignment -BeforeLines @('id bigint,', 'name varchar(100),') -AfterLines @('id bigint,', 'name varchar(20),')
$rows | ForEach-Object -Process { $_.Kind }
# Same
# Changed
```

### コンソールに色付きで出す

`ConvertTo-DiffText` は表示する内容だけを決め、出力はしません。色と「N 行省略」の文言は、使う側で決めます。

```powershell
foreach ($line in ConvertTo-DiffText -Rows $rows -ContextLine 3) {
    if ($line.Role -ceq 'Omitted') {
        Write-Host -Object ('{0}({1} 行省略)' -f $line.Gutter, $line.OmittedCount) -ForegroundColor DarkGray
        continue
    }
    Write-Host -Object $line.Gutter -NoNewline
    foreach ($segment in $line.Segments) {
        $color = if ($segment.Changed) { 'Yellow' } else { 'Gray' }
        Write-Host -Object $segment.Text -ForegroundColor $color -NoNewline
    }
    Write-Host
}
```

### HTML に保存する

```powershell
$html = ConvertTo-DiffHtml -Title 'settings' -Sections @(@{ Label = 'アプリ設定'; Rows = $rows })
[System.IO.File]::WriteAllText("$PWD\diff.html", $html, [System.Text.UTF8Encoding]::new($false))
```

1 つの文書に複数のセクションを並べられます。変更前か変更後を取得できずに比較できないセクションには、`Rows` の代わりに `Unverified` に理由の行を渡します。「差分なし」と見分けの付かない表示にしないためです。

```powershell
@{ Label = 'アプリ設定'; Rows = @(); Unverified = @('変更前の取得に失敗しました') }
```

## 戻り値の形

どれも型名の付いた `[PSCustomObject]` で返します。

| 関数 | 型名 | 項目 |
| :--- | :--- | :--- |
| `Get-DiffAlignment` | `TextDiff.DiffRow` | `Kind`（`Same` / `Changed` / `Deleted` / `Added`）、`LeftNo`、`RightNo`、`Left`、`Right`。行番号は 1 始まりで、片側にしか無い行の反対側は `$null` |
| `ConvertTo-DiffText` | `TextDiff.TextLine` | `Gutter`、`Role`（`Removed` / `Added` / `Context` / `Omitted`）、`Segments`、`OmittedCount`。`Omitted` の行は `Segments` が空で、畳んだ行数を `OmittedCount` に持つ。ほかの行の `OmittedCount` は 0 |
| （`Segments` の要素） | `TextDiff.Segment` | `Text`、`Changed`（行内で変わった部分なら `$true`） |
| `ConvertTo-DiffHtml` | （文字列） | HTML 文書全体 |

`ConvertTo-DiffText` の `-Rows` と、`ConvertTo-DiffHtml` のセクションの `Rows` には、`Get-DiffAlignment` の戻り値だけを渡せます。

詳しくは `Get-Help Get-DiffAlignment -Full` などで読めます。

## 開発

```powershell
Invoke-Pester -Path .\tests
Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1   # 何も出なければ合格
```

どちらも新しい `powershell.exe -NoProfile` の中で、リポジトリの直下で実行します。開発機と CI は次の版にそろえます。

| モジュール | 版 | 用途 |
| :--- | :--- | :--- |
| Pester | 5.9.0 | テスト |
| PSScriptAnalyzer | 1.25.0 | 静的解析 |
| Microsoft.PowerShell.PSResourceGet | 1.2.0 | 公開（CI だけで使う） |

書き方の決まりは [`CLAUDE.md`](CLAUDE.md) にあります。

## 公開の手順

1. `TextDiff/TextDiff.psd1` の `ModuleVersion` を上げ、`CHANGELOG.md` にその版の見出しを書く
2. main に取り込んだら、`v<版>` のタグ（例: `v1.0.1`）を push する
3. `.github/workflows/publish.yml` がテストを通したうえで PowerShell Gallery へ公開する

公開には、リポジトリの Secrets に `PSGALLERY_API_KEY` が要ります。一度公開した版は上書きも削除もできません。

## ライセンス

[MIT](LICENSE)
