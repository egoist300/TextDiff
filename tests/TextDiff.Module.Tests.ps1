#Requires -Version 5.1

# TextDiff モジュールとして正しく組み上がっているかのテスト。
#
# 他のテストは関数ごとの振る舞いを見る。
# ここはそれでは見えないもの、**モジュールとして読み込んだときにだけ起きること**と、ファイルの置き方を見る。

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

        It "Test-ModuleManifest を通る" {
            { Test-ModuleManifest -Path $script:manifestPath -ErrorAction Stop } | Should -Not -Throw
        }

        It "公開するものはワイルドカードを使わず列挙する" {
            # * にすると、Private に関数を足しただけで公開範囲が広がる
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

        It "CHANGELOG.md に今の版の見出しがある" {
            # Gallery に公開した版は上書きできない。何を変えた版なのかを先に書いておく
            $version = (Import-PowerShellDataFile -Path $script:manifestPath).ModuleVersion
            $changelog = Get-Content -LiteralPath (Join-Path -Path $script:repoRoot -ChildPath 'CHANGELOG.md') -Raw -Encoding UTF8

            $changelog | Should -MatchExactly ('(?m)^##\s+' + [regex]::Escape($version) + '\b')
        }
    }

    Context "公開範囲" {

        It "公開される関数は、Public に置いた関数とマニフェストの一覧に一致する" {
            # 置き場所と公開の一覧がずれると、Public にあるのに外から呼べない関数か、
            # Private にあるのに公開される関数ができる
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

        It "StrictMode が効いている" {
            $result = & $script:module { try { $null = $noSuchVariable; 'off' } catch { 'on' } }

            $result | Should -BeExactly 'on'
        }

        It "ErrorActionPreference が Stop になっている" {
            & $script:module { $ErrorActionPreference } | Should -BeExactly 'Stop'
        }

        It "呼び出し元の ErrorActionPreference は変えない" {
            # モジュールの設定が利用者のスクリプトに漏れると、利用者のエラー処理が変わってしまう。
            # 漏れる経路はグローバルの変数だけなので、グローバルの値を直接見る。
            # スクリプトのスコープで設定して読むと、グローバルが変わってもその変数が優先されて見えない
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

    Context "ファイルの置き方" {

        It "リポジトリのすべてのスクリプト（.ps1 / .psm1）が、#Requires -Version 5.1 と空行で始まる" {
            # 動作を確かめているのは Windows PowerShell 5.1 だけ。どのファイルから読み込まれても、
            # 5.1 より古い版では書き方の違いで壊れる前に、版の不足として止まるようにする。
            # 置き場所を先頭にそろえるのは、ファイルを開いてすぐ見えるようにするため。
            # 空行を挟むのは、直後にヘルプを書くスクリプトで、Get-Help がヘルプを認識するため
            $gitDir = (Join-Path -Path $script:repoRoot -ChildPath '.git') + [System.IO.Path]::DirectorySeparatorChar
            $scripts = @(Get-ChildItem -LiteralPath $script:repoRoot -File -Recurse -Force |
                    Where-Object -FilterScript { @('.ps1', '.psm1') -icontains $_.Extension -and -not $_.FullName.StartsWith($gitDir, [System.StringComparison]::OrdinalIgnoreCase) })
            $violations = foreach ($file in $scripts) {
                $relativePath = $file.FullName.Substring($script:repoRoot.Length + 1)
                # ReadAllText は先頭の BOM を取り除いて返す
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
            # 関数からファイルを名前だけで辿れる状態を保つ
            $violations = foreach ($file in Get-SourceFile) {
                $statements = @((Get-FileAst -Path $file.FullName).EndBlock.Statements)
                $functions = @($statements | Where-Object -FilterScript { $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] })
                if ($statements.Count -ne 1 -or $functions.Count -ne 1 -or $functions[0].Name -cne $file.BaseName) {
                    '{0}\{1}' -f $file.Directory.Name, $file.Name
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
            # 関数を消したのにテストだけ残ると、何を守っているのか分からないテストになる
            $sourceNames = @(Get-SourceFile | ForEach-Object -MemberName BaseName)
            $wholeRepo = @('TextDiff.Module', 'FileEncoding', 'CommentBasedHelp', 'CodingRules')
            $orphans = @(Get-ChildItem -LiteralPath $script:testsRoot -Filter *.Tests.ps1 -File |
                    ForEach-Object -Process { $_.Name -creplace '\.Tests\.ps1$', '' } |
                    Where-Object -FilterScript { $sourceNames -cnotcontains $_ -and $wholeRepo -cnotcontains $_ })

            (@($orphans) -join ', ') | Should -BeNullOrEmpty
        }

        It "モジュールのフォルダに *.Tests.ps1 が紛れ込んでも読み込まない" {
            # 本体は各フォルダの .ps1 をまとめて読み込むため、テストが紛れ込むと
            # 利用者の環境でテストコードが展開される。リポジトリは汚さず、写した先で確かめる
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

        It "角括弧を含むフォルダに置いても、関数をすべて読み込む" {
            # -Path はワイルドカードとして解釈し、1 ファイルも見つけられない。
            # 後始末は自分で -LiteralPath で行う。TestDrive の片付けは -Path で消すため、
            # 角括弧のフォルダを残すと Pester 自身が落ちる
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
