# TextDiff

[![CI](https://github.com/egoist300/TextDiff/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/egoist300/TextDiff/actions/workflows/ci.yml?query=branch%3Amain) [![PowerShell Gallery](https://img.shields.io/powershellgallery/v/TextDiff.svg)](https://www.powershellgallery.com/packages/TextDiff)

変更前と変更後の 2 つの行の配列を比較して差分を算出し、コンソール表示用の行と、左右に並べて表示する HTML に変換する PowerShell モジュールです。

- 行の対応付けに Myers 法を使用します。変更行が少ないほど高速で、1000 行のうち 5 行に変更がある場合に約 14 ミリ秒でした（Windows PowerShell 5.1 での実測）
- 隣接する削除行と追加行のうち、類似する組だけを 1 行の変更として対応付け、行内の変更箇所を単語単位で検出します
- HTML は CSS と JavaScript を埋め込んだ単一のファイルで、外部のリソースを読み込みません。別のマシンにコピーしても同じ表示になります

HTML の見出しや凡例などの文言は日本語です。

## 動作環境

Windows PowerShell 5.1。

## インストール

```powershell
Install-Module -Name TextDiff -Scope CurrentUser -RequiredVersion 1.0.0
```

`C:\Users\<ユーザー名>\Documents\WindowsPowerShell\Modules\TextDiff\1.0.0\` にインストールされます。

インターネットに接続できない環境で使用する場合は、接続できる環境で保存してから、フォルダごとコピーします。

```powershell
Save-Module -Name TextDiff -RequiredVersion 1.0.0 -Path .\Modules
# コピー先の環境で
Import-Module -Name .\Modules\TextDiff\1.0.0\TextDiff.psd1
```

## 使い方

### 行を対応付ける

```powershell
$rows = Get-DiffAlignment -BeforeLines @('id bigint,', 'name varchar(100),') -AfterLines @('id bigint,', 'name varchar(20),')
$rows | ForEach-Object -Process { $_.Kind }
# Same
# Changed
```

### コンソールに色付きで表示する

`ConvertTo-DiffText` は表示する行を生成するだけで、コンソールへの出力はしません。色と「N 行省略」の文言は、呼び出し側で指定します。

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

1 つの文書に複数のセクションを配置できます。変更前または変更後を取得できず、比較できないセクションには、`Rows` の代わりに `Unverified` に理由の行を渡します。「差分なし」と区別できない表示を防ぐためです。

```powershell
@{ Label = 'アプリ設定'; Rows = @(); Unverified = @('変更前の取得に失敗しました') }
```

## 開発

開発に参加する方法は [CONTRIBUTING.md](CONTRIBUTING.md) にあります。

## 変更履歴

[CHANGELOG.md](CHANGELOG.md)

## ライセンス

[MIT](LICENSE)
