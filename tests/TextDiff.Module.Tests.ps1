#Requires -Version 5.1

# TextDiff モジュール全体の構成のテスト。
#
# ほかのテストは関数ごとの動作を確認する。
# ここでは、モジュールとして読み込んだときにだけ起きることと、ファイルの配置を確認する。

BeforeAll {
    Set-StrictMode -Version 3.0
    $script:repoRoot = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')).Path
    $script:moduleRoot = Join-Path -Path $script:repoRoot -ChildPath 'TextDiff'
    $script:manifestPath = Join-Path -Path $script:moduleRoot -ChildPath 'TextDiff.psd1'
    $script:testsRoot = Join-Path -Path $script:repoRoot -ChildPath 'tests'

    function Get-SourceFile {
        <#
        .SYNOPSIS
            モジュールの関数のファイルを返す。
        .PARAMETER Folder
            対象のフォルダ名（Private / Public）の一覧。
        #>
        param([string[]]$Folder = @('Private', 'Public'))
        foreach ($folderName in $Folder) {
            Get-ChildItem -LiteralPath (Join-Path -Path $script:moduleRoot -ChildPath $folderName) -Filter *.ps1 -File -ErrorAction Stop
        }
    }

    function Get-FileAst {
        <#
        .SYNOPSIS
            ファイルを構文解析し、構文木を返す。
        .PARAMETER Path
            解析する .ps1 のパス。
        #>
        param([string]$Path)
        return [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
    }
}

Describe "TextDiff モジュール" {

    BeforeAll {
        $script:module = Import-Module -Name $script:manifestPath -Force -PassThru -ErrorAction Stop
    }

    AfterAll {
        Remove-Module -Name TextDiff -ErrorAction SilentlyContinue
    }

    Context "マニフェスト" {

        It "Test-ModuleManifest の検証に成功する" {
            { Test-ModuleManifest -Path $script:manifestPath -ErrorAction Stop } | Should -Not -Throw
        }

        It "公開するものはワイルドカードを使わず列挙する" {
            # * にすると、Private に関数を追加しただけで公開範囲が広がるため。
            $data = Import-PowerShellDataFile -Path $script:manifestPath

            (@($data.FunctionsToExport) -ccontains '*') | Should -BeFalse
            @($data.CmdletsToExport).Count | Should -BeExactly 0
            @($data.VariablesToExport).Count | Should -BeExactly 0
            @($data.AliasesToExport).Count | Should -BeExactly 0
        }

        It "PowerShell Gallery が表示するライセンスとプロジェクトの URL を持つ" {
            $psData = (Import-PowerShellDataFile -Path $script:manifestPath).PrivateData.PSData

            $psData.LicenseUri | Should -Not -BeNullOrEmpty
            $psData.ProjectUri | Should -Not -BeNullOrEmpty
        }

        It "CHANGELOG.md に今のバージョンの見出しがある" {
            # PowerShell Gallery に公開したバージョンは上書きできないため、変更内容を公開前に記載する。
            $version = (Import-PowerShellDataFile -Path $script:manifestPath).ModuleVersion
            $changelog = Get-Content -LiteralPath (Join-Path -Path $script:repoRoot -ChildPath 'CHANGELOG.md') -Raw -Encoding UTF8

            $changelog | Should -MatchExactly ('(?m)^##\s+' + [regex]::Escape($version) + '\b')
        }
    }

    Context "公開範囲" {

        It "公開される関数は、Public に配置した関数とマニフェストの一覧に一致する" {
            # 配置と公開の一覧が一致しないと、Public にあるのに外から呼べない関数か、
            # Private にあるのに公開される関数ができるため。
            $inPublic = @(Get-SourceFile -Folder Public | ForEach-Object -MemberName BaseName | Sort-Object -CaseSensitive)
            $declared = @((Import-PowerShellDataFile -Path $script:manifestPath).FunctionsToExport | Sort-Object -CaseSensitive)
            $exported = @($script:module.ExportedFunctions.Keys | Sort-Object -CaseSensitive)

            ($declared -join ', ') | Should -BeExactly ($inPublic -join ', ')
            ($exported -join ', ') | Should -BeExactly ($inPublic -join ', ')
        }

        It "Private の関数もモジュールの中に読み込まれている" {
            $missing = @(Get-SourceFile -Folder Private | ForEach-Object -MemberName BaseName | Where-Object -FilterScript {
                    -not (& $script:module { param($name) [bool](Get-Command -Name $name -ErrorAction SilentlyContinue) } $_)
                })

            ($missing -join ', ') | Should -BeNullOrEmpty
        }
    }

    Context "モジュールの中の実行条件" {

        It "StrictMode が有効になっている" {
            $result = & $script:module { try { $null = $noSuchVariable; 'off' } catch { 'on' } }

            $result | Should -BeExactly 'on'
        }

        It "ErrorActionPreference が Stop になっている" {
            & $script:module { $ErrorActionPreference } | Should -BeExactly 'Stop'
        }

        It "呼び出し元の ErrorActionPreference は変更しない" {
            # モジュールの設定が利用者のスクリプトに漏れると、利用者のエラー処理が変化する。
            # 漏れる経路はグローバル変数だけのため、グローバル変数の値を直接確認する。
            # スクリプトのスコープで設定して読み取ると、グローバル変数が変更されてもスクリプトの変数が優先され、検出できない。
            $probePath = Join-Path -Path $TestDrive -ChildPath 'probe.ps1'
            $probe = @"
`$global:ErrorActionPreference = 'Continue'
Import-Module -Name '$script:manifestPath' -Force
`$global:ErrorActionPreference
"@
            [System.IO.File]::WriteAllText($probePath, $probe, ([System.Text.UTF8Encoding]::new($true)))

            $output = @(powershell -NoProfile -Command "& '$probePath'" | ForEach-Object -Process { "$_" })
            $probeExitCode = $LASTEXITCODE

            $probeExitCode | Should -BeExactly 0
            $output | Should -BeExactly @('Continue')
        }
    }

    Context "ファイルの配置" {

        It "リポジトリのすべてのスクリプト（.ps1 / .psm1）が、#Requires -Version 5.1 と空行で始まる" {
            # 動作を確認しているのは Windows PowerShell 5.1 だけ。どのファイルから読み込まれても、
            # 5.1 より古いバージョンでは、構文の違いで失敗する前に、バージョンの不足として停止させる。
            # 先頭に配置するのは、ファイルを開いてすぐ確認できるようにするため。
            # 空行を挟むのは、直後にヘルプを書くスクリプトで、Get-Help がヘルプを認識するため。
            $gitDir = (Join-Path -Path $script:repoRoot -ChildPath '.git') + [System.IO.Path]::DirectorySeparatorChar
            $scripts = @(Get-ChildItem -LiteralPath $script:repoRoot -File -Recurse -Force |
                    Where-Object -FilterScript { @('.ps1', '.psm1') -icontains $_.Extension -and -not $_.FullName.StartsWith($gitDir, [System.StringComparison]::OrdinalIgnoreCase) })
            $violations = foreach ($file in $scripts) {
                $relativePath = $file.FullName.Substring($script:repoRoot.Length + 1)
                # ReadAllText は先頭の BOM を除去して返す。
                $lines = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8) -csplit "`n"
                if ($lines.Count -lt 2 -or $lines[0] -cne '#Requires -Version 5.1' -or $lines[1] -cne '') {
                    "$relativePath（先頭の 2 行が「#Requires -Version 5.1」と空行ではない）"
                    continue
                }
                $requirements = (Get-FileAst -Path $file.FullName).ScriptRequirements
                if ($null -eq $requirements -or $requirements.RequiredPSVersion -cne [version]'5.1') {
                    "$relativePath（PowerShell が #Requires として読んでいない）"
                }
            }

            $scripts.Count | Should -BeGreaterThan 30
            (@($violations) -join ', ') | Should -BeNullOrEmpty
        }

        It "Public と Private は 1 ファイル 1 関数で、ファイル名は関数名と同じ" {
            # 関数からファイルを名前だけで辿れる状態を保つ。
            # 関数の中で定義した関数も対象にする。最上位だけを対象にすると、関数の中に補助関数を配置する形を検出できない。
            $violations = foreach ($file in Get-SourceFile) {
                $fileAst = Get-FileAst -Path $file.FullName
                $statements = @($fileAst.EndBlock.Statements)
                $functions = @($fileAst.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
                if ($statements.Count -ne 1 -or $functions.Count -ne 1 -or $functions[0].Name -cne $file.BaseName) {
                    '{0}\{1}（関数: {2}）' -f $file.Directory.Name, $file.Name, (($functions | ForEach-Object -MemberName Name) -join ', ')
                }
            }

            @(Get-SourceFile).Count | Should -BeGreaterThan 0
            (@($violations) -join ', ') | Should -BeNullOrEmpty
        }

        It "すべての関数に、同じ名前のテストファイルがある" {
            $testNames = @(Get-ChildItem -LiteralPath $script:testsRoot -Filter *.Tests.ps1 -File | ForEach-Object -Process { $_.Name -creplace '\.Tests\.ps1$', '' })
            $missing = @(Get-SourceFile | ForEach-Object -MemberName BaseName | Where-Object -FilterScript { $testNames -cnotcontains $_ })

            (@($missing) -join ', ') | Should -BeNullOrEmpty
        }

        It "すべてのテストファイルに、対応する関数か全体の検査がある" {
            # 関数を削除したのにテストだけ残ると、何を確認しているのか分からないテストになるため。
            $sourceNames = @(Get-SourceFile | ForEach-Object -MemberName BaseName)
            $wholeRepo = @('TextDiff.Module', 'FileEncoding', 'CommentBasedHelp', 'CodingRules')
            $orphans = @(Get-ChildItem -LiteralPath $script:testsRoot -Filter *.Tests.ps1 -File |
                    ForEach-Object -Process { $_.Name -creplace '\.Tests\.ps1$', '' } |
                    Where-Object -FilterScript { $sourceNames -cnotcontains $_ -and $wholeRepo -cnotcontains $_ })

            (@($orphans) -join ', ') | Should -BeNullOrEmpty
        }

        It "モジュールのフォルダに *.Tests.ps1 が紛れ込んでも読み込まない" {
            # 本体は各フォルダの .ps1 をまとめて読み込むため、テストが紛れ込むと
            # 利用者の環境でテストコードが展開される。リポジトリは変更せず、複製した先で確認する。
            $copyRoot = Join-Path -Path $TestDrive -ChildPath 'TextDiff'
            Copy-Item -LiteralPath $script:moduleRoot -Destination $copyRoot -Recurse
            $strayPath = Join-Path -Path $copyRoot -ChildPath 'Private\Stray.Tests.ps1'
            [System.IO.File]::WriteAllText($strayPath, "function Test-StrayLoaded { 'loaded' }`n", ([System.Text.UTF8Encoding]::new($true)))

            $copy = Import-Module -Name (Join-Path -Path $copyRoot -ChildPath 'TextDiff.psd1') -Force -PassThru
            try {
                & $copy { [bool](Get-Command -Name Test-StrayLoaded -ErrorAction SilentlyContinue) } | Should -BeFalse
            }
            finally {
                Remove-Module -ModuleInfo $copy -ErrorAction SilentlyContinue
            }
        }

        It "角括弧を含むフォルダに配置しても、関数をすべて読み込む" {
            # -Path は角括弧をワイルドカードとして解釈し、1 ファイルも見つけられない。
            # 後片付けは -LiteralPath で行う。TestDrive の後片付けは -Path で削除するため、
            # 角括弧を含むフォルダを残すと Pester 自身が失敗する。
            $releaseRoot = Join-Path -Path $TestDrive -ChildPath 'release[2026]'
            New-Item -ItemType Directory -Path $releaseRoot -Force | Out-Null
            $copy = $null
            try {
                $copyRoot = Join-Path -Path $releaseRoot -ChildPath 'TextDiff'
                Copy-Item -LiteralPath $script:moduleRoot -Destination $copyRoot -Recurse
                $copy = Import-Module -Name (Join-Path -Path $copyRoot -ChildPath 'TextDiff.psd1') -Force -PassThru

                $copy.ExportedFunctions.Count | Should -BeExactly $script:module.ExportedFunctions.Count
                & $copy { [bool](Get-Command -Name Get-MyersOperation -ErrorAction SilentlyContinue) } | Should -BeTrue
            }
            finally {
                if ($null -ne $copy) { Remove-Module -ModuleInfo $copy -ErrorAction SilentlyContinue }
                Remove-Item -LiteralPath $releaseRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
