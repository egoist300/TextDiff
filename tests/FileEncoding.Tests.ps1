#Requires -Version 5.1

# ファイルの文字コード規約を機械で守るためのテスト。
#
# このリポジトリでは拡張子ごとに BOM の要否が違う。間違えると派手に壊れる
# （.ps1 を BOM なしで保存すると、日本語ロケールの Windows PowerShell 5.1 は ANSI として読み、
# コメントが文字化けしてパースエラーになる）。
#
# 書き込み手段によって既定が違うのが事故の元になる。
#   Set-Content / Out-File -Encoding utf8            → BOM 付き
#   [System.IO.File]::WriteAllText（既定）           → BOM なし
# エディタや別のツールが 1 ファイル触っただけで規約から外れうるため、目視ではなくテストで検出する。

BeforeAll {
    Set-StrictMode -Version 3.0
    $script:repoRoot = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')).Path

    # BOM 付きで保存すべき拡張子。PowerShell が読み込むファイルはすべて同じ理由で必要になる。
    # .psd1 は BOM が無いと日本語が文字化けし、マニフェストとして読み込めなくなる
    $script:bomExtensions = @('.ps1', '.psd1', '.psm1')
    $script:noBomExtensions = @('.md', '.yml', '.yaml', '.html', '.json')

    # 行の書式（末尾の改行・行末の空白）を検査する対象。拡張子を持たない設定ファイルも含める。
    # .NET は '.gitignore' のような名前を「拡張子そのもの」と解釈するので、この書き方で拾える
    $script:textExtensions = $script:bomExtensions + $script:noBomExtensions + @('.gitignore', '.gitattributes', '.editorconfig')

    # .git の中はリポジトリの管理情報で、規約の対象外
    function Get-TargetFile {
        <#
        .SYNOPSIS
            リポジトリの中から、指定した拡張子のファイルを返す。
        .PARAMETER Extension
            対象の拡張子（小文字、ドット付き）の一覧。
        #>
        param([string[]]$Extension)
        $gitDir = (Join-Path -Path $script:repoRoot -ChildPath '.git') + [System.IO.Path]::DirectorySeparatorChar
        Get-ChildItem -LiteralPath $script:repoRoot -File -Recurse -Force |
            Where-Object -FilterScript { $Extension -ccontains $_.Extension.ToLowerInvariant() } |
            Where-Object -FilterScript { -not $_.FullName.StartsWith($gitDir, [System.StringComparison]::OrdinalIgnoreCase) }
    }

    function Test-Utf8Bom {
        <#
        .SYNOPSIS
            ファイルの先頭 3 バイトが UTF-8 の BOM（EF BB BF）かを返す。
        .PARAMETER Path
            調べるファイルのパス。
        #>
        param([string]$Path)
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        return ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    }

    function Get-RelativePath {
        <#
        .SYNOPSIS
            リポジトリの直下からの相対パスを返す。失敗したときに、どのファイルかを一目で分かるようにする。
        .PARAMETER Path
            リポジトリの中のファイルの完全パス。
        #>
        param([string]$Path)
        return $Path.Substring($script:repoRoot.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar)
    }
}

Describe "ファイルの文字コード規約" {

    It ".ps1 / .psd1 / .psm1 はすべて BOM 付き UTF-8 で保存されている" {
        $violations = @(
            Get-TargetFile -Extension $script:bomExtensions |
                Where-Object -FilterScript { -not (Test-Utf8Bom -Path $_.FullName) } |
                ForEach-Object -Process { Get-RelativePath -Path $_.FullName }
        )

        # 検査対象が 0 件だと無条件に通ってしまうため、件数そのものも確認する
        @(Get-TargetFile -Extension $script:bomExtensions).Count | Should -BeGreaterThan 0
        $violations -join ', ' | Should -BeNullOrEmpty
    }

    It ".ps1 / .psd1 / .psm1 の BOM は 1 つだけ" {
        # BOM を二重に付けると、2 つ目が普通の文字として読まれ、先頭の [CmdletBinding()] や
        # #Requires がスクリプトの先頭と見なされなくなる（構文エラーになる）
        $violations = @(
            Get-TargetFile -Extension $script:bomExtensions | ForEach-Object -Process {
                $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
                if ($bytes.Length -ge 6 -and $bytes[3] -eq 0xEF -and $bytes[4] -eq 0xBB -and $bytes[5] -eq 0xBF) {
                    Get-RelativePath -Path $_.FullName
                }
            }
        )

        $violations -join ', ' | Should -BeNullOrEmpty
    }

    It ".md / .yml / .html / .json には BOM が付いていない" {
        # .yml は GitHub Actions のワークフローで、BOM があると解析に失敗する。
        # .json は ConvertFrom-Json を壊す
        $violations = @(
            Get-TargetFile -Extension $script:noBomExtensions |
                Where-Object -FilterScript { Test-Utf8Bom -Path $_.FullName } |
                ForEach-Object -Process { Get-RelativePath -Path $_.FullName }
        )

        @(Get-TargetFile -Extension $script:noBomExtensions).Count | Should -BeGreaterThan 0
        $violations -join ', ' | Should -BeNullOrEmpty
    }

    It "改行は LF に統一されている" {
        # .gitattributes で `* -text` を指定しており、git は改行を一切変換しない。
        # 書いた側が CRLF を混ぜたらそのまま入り、見た目も動作も変わらないため目視では見つからない
        $extensions = $script:bomExtensions + $script:noBomExtensions
        $violations = @(
            Get-TargetFile -Extension $extensions | ForEach-Object -Process {
                $text = [System.IO.File]::ReadAllText($_.FullName, [System.Text.Encoding]::UTF8)
                $crlf = ([regex]::Matches($text, "`r`n")).Count
                if ($crlf -gt 0) { "{0} ({1} 行)" -f (Get-RelativePath -Path $_.FullName), $crlf }
            }
        )

        @(Get-TargetFile -Extension $extensions).Count | Should -BeGreaterThan 0
        $violations -join ', ' | Should -BeNullOrEmpty
    }

    It "テキストファイルは改行で終わる" {
        # 最終行に改行が無いと、その後ろに追記したときに触っていない行が変わったように見える
        $violations = @(
            Get-TargetFile -Extension $script:textExtensions | ForEach-Object -Process {
                $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
                if ($bytes.Length -gt 0 -and $bytes[-1] -ne 0x0A) { Get-RelativePath -Path $_.FullName }
            }
        )

        @(Get-TargetFile -Extension $script:textExtensions).Count | Should -BeGreaterThan 0
        $violations -join ', ' | Should -BeNullOrEmpty
    }

    It "行末に空白を残さない（Markdown を除く）" {
        # 見えない差分の元になる。Markdown だけは行末の 2 スペースが改行の意味を持つので除く
        $extensions = @($script:textExtensions | Where-Object -FilterScript { $_ -cne '.md' })
        $violations = @(
            Get-TargetFile -Extension $extensions | ForEach-Object -Process {
                $text = [System.IO.File]::ReadAllText($_.FullName, [System.Text.Encoding]::UTF8)
                $count = ([regex]::Matches($text, '(?m)[ \t]+$')).Count
                if ($count -gt 0) { "{0} ({1} 行)" -f (Get-RelativePath -Path $_.FullName), $count }
            }
        )

        $violations -join ', ' | Should -BeNullOrEmpty
    }

    It ".ps1 / .psd1 / .psm1 が UTF-8 として破綻なくデコードできる" {
        # BOM は付いていても中身が別のエンコーディング（Shift_JIS 等）なら同じように壊れる
        $strictUtf8 = [System.Text.UTF8Encoding]::new($true, $true)
        $violations = @(
            Get-TargetFile -Extension $script:bomExtensions | ForEach-Object -Process {
                try {
                    [void]$strictUtf8.GetString([System.IO.File]::ReadAllBytes($_.FullName))
                }
                catch {
                    Get-RelativePath -Path $_.FullName
                }
            }
        )

        $violations -join ', ' | Should -BeNullOrEmpty
    }
}
