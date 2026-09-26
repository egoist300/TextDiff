#Requires -Version 5.1

# モジュールは、呼び出し元で設定した StrictMode と $ErrorActionPreference を継承しない。
# 関数はどれも「未定義の変数は例外」「失敗は例外」が前提のため、ここで設定する。
# 設定はこのモジュールの中だけ適用され、呼び出し元に漏洩しない。
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# -Path はフォルダ名の角括弧（release[2026] 等）をワイルドカードと解釈し、1 ファイルも検知できない。
# モジュール自体は読み込めるため、最初の関数呼び出しまで検知できない。
# -Filter は 8.3 形式の短い名前に一致する（*.ps1 が .ps1x にも一致する）ため、拡張子を再確認する。
foreach ($folder in @('Private', 'Public')) {
    $sourceFiles = Get-ChildItem -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath $folder) -Filter '*.ps1' -File |
        Where-Object -FilterScript { $_.Extension -ieq '.ps1' -and $_.Name -inotlike '*.Tests.ps1' } |
        Sort-Object -CaseSensitive -Property Name
    foreach ($sourceFile in $sourceFiles) {
        . $sourceFile.FullName
    }
}
