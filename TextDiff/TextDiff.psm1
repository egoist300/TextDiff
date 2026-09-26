# TextDiff モジュールの読み込み係。関数はフォルダごとに置き、ここでは実行条件を整えて読み込むだけ。
#
#   Private\  非公開の関数。1 つの関数に 1 ファイルで、ファイル名は関数名と同じ
#   Public\   公開する関数（TextDiff.psd1 の FunctionsToExport に列挙したもの）。置き方は Private\ と同じ
#
# 【実行条件をここで設定する理由】
# モジュールは、呼び出し元のスクリプトで設定した StrictMode と $ErrorActionPreference を受け継がない。
# 関数はどれも「未定義の変数は例外」「失敗は例外」を前提に書かれているため、ここで自分で設定する。
# 設定はこのモジュールの中にだけ効き、呼び出し元には漏れない
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# 【*.Tests.ps1 を除く理由】
# 各フォルダの .ps1 はまとめて読み込むため、テストが紛れ込むと利用者の環境でテストコードまで展開される。
#
# 【-LiteralPath で列挙する理由】
# 置き場所のフォルダ名に角括弧（release[2026] 等）があると、-Path はワイルドカードとして解釈して
# 1 ファイルも見つけない。モジュール自体は読み込めてしまうため、最初の関数呼び出しで止まる。
# -Filter は 8.3 形式の短い名前にも一致する（*.ps1 が .ps1x にも当たる）ため、拡張子は改めて確かめる
foreach ($folder in @('Private', 'Public')) {
    $sourceFiles = Get-ChildItem -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath $folder) -Filter '*.ps1' -File |
        Where-Object -FilterScript { $_.Extension -ieq '.ps1' -and $_.Name -inotlike '*.Tests.ps1' } |
        Sort-Object -CaseSensitive -Property Name
    foreach ($sourceFile in $sourceFiles) {
        . $sourceFile.FullName
    }
}
