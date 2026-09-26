# 開発への参加

TextDiff の開発と公開に必要な情報です。

## 開発環境

Windows PowerShell 5.1 だけを対象とします。開発機と CI では、次のバージョンのモジュールを使用します。

| モジュール | バージョン | 用途 |
| :--- | :--- | :--- |
| Pester | 5.9.0 | テスト |
| PSScriptAnalyzer | 1.25.0 | 静的解析。カスタムルールのテスト（`tests/CodingRules.Tests.ps1`）でも使用する |
| Microsoft.PowerShell.PSResourceGet | 1.2.0 | 公開（CI だけで使用する） |

バージョンを変更するときは、`.github/workflows/` の各ワークフローのバージョンも合わせて変更します。

開発機には、Pester と PSScriptAnalyzer をインストールします。Pester に `-SkipPublisherCheck` が必要なのは、Windows に同梱されている Pester 3.4.0 と署名者が異なるためです。

```powershell
Install-Module -Name Pester -RequiredVersion 5.9.0 -Scope CurrentUser -Force -SkipPublisherCheck
Install-Module -Name PSScriptAnalyzer -RequiredVersion 1.25.0 -Scope CurrentUser -Force
```

## テストと静的解析

新しい `powershell.exe -NoProfile` を起動し、リポジトリの直下で実行します。プロファイルや実行中のセッションの状態の影響を受けないようにするためです。

```powershell
Import-Module -Name Pester -RequiredVersion 5.9.0
Invoke-Pester -Path .\tests
Import-Module -Name PSScriptAnalyzer -RequiredVersion 1.25.0
Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1   # 指摘が 0 件なら合格
```

`Import-Module` でバージョンを指定するのは、指定しないと、インストール済みの最も新しいバージョンが読み込まれるためです。
静的解析の設定ファイルはカスタムルールを相対パスで指定しているため、リポジトリの直下以外で実行すると、カスタムルールを読み込めません。

## Issue と Pull Request

- 不具合の報告には、再現する入力、期待する結果、実際の結果、`$PSVersionTable.PSVersion` の値を記載する
- 公開する関数の引数や戻り値の形を変更する場合は、先に Issue で相談する
- 不具合を修正する Pull Request には、その不具合を再現するテストを追加する
- Pull Request は main に対して作成し、CI（テスト、静的解析、パッケージの作成の確認）が成功していることを確認する

## コーディング規約

括弧内は、その規約を検査するテストです。

### ファイルの構成

- 1 ファイルに 1 関数を定義し、ファイル名を関数名と一致させる。公開する関数は `TextDiff/Public/` に配置し、`TextDiff.psd1` の `FunctionsToExport` と一致させる。それ以外の関数は `TextDiff/Private/` に配置する（`tests/TextDiff.Module.Tests.ps1`）
- 関数ごとに `tests/<関数名>.Tests.ps1` を作成する（`tests/TextDiff.Module.Tests.ps1`）
- すべての `.ps1` と `.psm1` は、1 行目に `#Requires -Version 5.1` を記述し、2 行目を空行にする。空行が無いと、`Get-Help` がヘルプを認識しない（`tests/TextDiff.Module.Tests.ps1`）
- `.ps1` `.psd1` `.psm1` は BOM 付きの UTF-8、`.md` `.yml` `.json` `.html` は BOM なしの UTF-8 で保存する。改行コードはすべて LF にする（`tests/FileEncoding.Tests.ps1`）

### ヘルプとコメント

- すべての関数（テストの補助関数と、関数の中で定義した関数を含む）に、すべての引数の `.PARAMETER` を含むヘルプを記述する。公開する関数には `.EXAMPLE` を 1 つ以上記述する（`tests/CommentBasedHelp.Tests.ps1`）
- ヘルプには、関数の動作、各引数の意味、戻り値を記述する。その実装を選択した理由は、ヘルプではなく、該当するコードの直前のコメントに記述する
- コメントは日本語で記述する。変更の経緯はコメントではなく、コミットメッセージに記述する

### 設計

- モジュールは、コンソールの色と、HTML の見出し以外の文言を持たない。色と文言（`OmittedCount` から作成する「N 行省略」の行など）は呼び出し側で指定する

### 静的解析のカスタムルール

既定のルールに加えて、`tools/PSScriptAnalyzerRules/CodingRules.psm1` のカスタムルールで次の規約を検査します。各ルールが違反を検出することは、`tests/CodingRules.Tests.ps1` で確認しています。

- バッククォート（`` ` ``）で行を継続しない
- 1 文字の変数名を使用しない（`$_` などの自動変数を除く）
- `[bool]` の引数を使用しない（`[switch]` を使用する）
- コマンドの引数は名前付きで指定する
- メソッドの引数の中の `-f` は括弧で囲む
- `Start-Process` を使用しない
- 単独で実行するスクリプトには、`#Requires -Version 5.1` と、すべての引数を記述したヘルプを付ける
- 比較演算子は、大文字と小文字を区別する場合は `-ceq` のように `c` を、区別しない場合は `-ieq` のように `i` を付けて明示する。数値、`$null`、真偽値の定数と比較する `-eq` と `-ne` は対象外
- `Should` では大文字と小文字を区別して比較する。`-Be`、`-Match`、`-BeLike` の代わりに `-BeExactly`、`-MatchExactly`、`-BeLikeExactly` を、`-Contain` と `-BeIn` の代わりに `-ccontains` の結果を `-BeTrue` で確認する。`-Throw` はメッセージではなく `-ExceptionType` か `-ErrorId` で確認する

## バージョンの付け方

公開する範囲（公開する 3 つの関数、その引数、戻り値の形、生成する HTML）について、セマンティック バージョニングに従います。

- メジャー: 呼び出し側の変更が必要な変更（引数の削除や名前の変更、戻り値の形の変更）
- マイナー: 引数、関数、`ConvertTo-DiffHtml` のセクションの省略可能なキーの追加
- パッチ: それ以外

## 公開手順

メンテナーが実行する手順です。

### 初回の準備

PowerShell Gallery で API キーを作成し、リポジトリの Secrets に `PSGALLERY_API_KEY` として登録します。API キーは、対象のパッケージを TextDiff に限定し、公開（Push）の権限だけを付与します。

### バージョンごとの手順

1. `TextDiff/TextDiff.psd1` の `ModuleVersion` を更新し、`CHANGELOG.md` にそのバージョンの見出しと変更内容を追加する
2. main にマージした後、`v<バージョン>` のタグ（例: `v1.0.1`）を push する

タグを push すると、`.github/workflows/publish.yml` がテストを実行し、成功した場合に PowerShell Gallery へ公開します。タグと `ModuleVersion` が一致しない場合は公開しません。
一度公開したバージョンは上書きも削除もできないため、手順 1 の内容を確認してからタグを push します。
