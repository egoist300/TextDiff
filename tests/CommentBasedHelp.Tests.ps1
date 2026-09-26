#Requires -Version 5.1

# コメントベースヘルプが実装とずれていないかを機械で検査する。
#
# ヘルプはずれても lint もテストも落ちない。読む人はヘルプを信じるので、
# 書いていない引数は「無い」と受け取られる。
# 検査するのは対応関係だけで、説明文の中身は見ない。

BeforeAll {
    Set-StrictMode -Version 3.0
    $script:repoRoot = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')).Path

    # すべての関数（テストの補助関数と、関数の中で定義した関数を含む）で、ヘルプと引数の記載を必須にする。
    # 公開する関数は Get-Help で読む人がいるので、使用例も必須にする
    function Get-PublicSourceFile {
        <#
        .SYNOPSIS
            公開する関数のファイルを返す。
        #>
        Get-ChildItem -LiteralPath (Join-Path -Path $script:repoRoot -ChildPath 'TextDiff\Public') -Filter *.ps1 -File -ErrorAction Stop
    }

    function Get-RepositoryScriptFile {
        <#
        .SYNOPSIS
            リポジトリの中の .ps1 と .psm1 をすべて返す（.git の中を除く）。
        #>
        $gitDir = (Join-Path -Path $script:repoRoot -ChildPath '.git') + [System.IO.Path]::DirectorySeparatorChar
        Get-ChildItem -LiteralPath $script:repoRoot -File -Recurse -Force -ErrorAction Stop |
            Where-Object -FilterScript { @('.ps1', '.psm1') -icontains $_.Extension -and -not $_.FullName.StartsWith($gitDir, [System.StringComparison]::OrdinalIgnoreCase) }
    }

    function Get-FileAst {
        <#
        .SYNOPSIS
            ファイルを構文解析し、構文木を返す。
        .PARAMETER Path
            解析する .ps1 のパス。
        #>
        param([string]$Path)
        $tokens = $null
        $errors = $null
        return [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    }

    # ヘルプが記載しているパラメータ名と、実際の param() を突き合わせる。
    # 引数名は PowerShell の名前なので、大小文字を区別せずに比べる
    function Get-HelpMismatch {
        <#
        .SYNOPSIS
            ヘルプの .PARAMETER と実際の param() の食い違いを、1 件 1 行の説明で返す。
        .PARAMETER HelpContent
            FunctionDefinitionAst.GetHelpContent() の戻り値。ヘルプが無い関数では $null。
        .PARAMETER ParamBlock
            関数の ParamBlockAst。引数を取らない関数では $null。
        .PARAMETER Label
            食い違いの説明の先頭に付ける、関数を示す文字列。
        .PARAMETER RequireComplete
            実在する引数がすべて記載されていることまで求める。
        #>
        param($HelpContent, $ParamBlock, [string]$Label, [switch]$RequireComplete)

        $found = [System.Collections.Generic.List[string]]::new()
        $documented = @()
        if ($null -ne $HelpContent -and $null -ne $HelpContent.Parameters) { $documented = @($HelpContent.Parameters.Keys) }
        $actual = @()
        if ($null -ne $ParamBlock) { $actual = @($ParamBlock.Parameters | ForEach-Object -Process { $_.Name.VariablePath.UserPath }) }

        foreach ($name in $documented) {
            if ($actual -inotcontains $name) { $found.Add("$Label : 実在しない '$name' を記載している") }
        }
        if ($RequireComplete) {
            foreach ($name in $actual) {
                if ($documented -inotcontains $name) { $found.Add("$Label : '$name' が未記載") }
            }
        }
        return $found.ToArray()
    }

    $script:functionAstFilter = {
        param($Node)
        $Node -is [System.Management.Automation.Language.FunctionDefinitionAst]
    }
}

Describe "コメントベースヘルプと実装の対応" {

    It "すべての関数にヘルプがあり、.PARAMETER と param() が一致する" {
        $violations = foreach ($file in Get-RepositoryScriptFile) {
            foreach ($function in (Get-FileAst -Path $file.FullName).FindAll($script:functionAstFilter, $true)) {
                $label = "$($file.Name)/$($function.Name)"
                $help = $function.GetHelpContent()
                if ($null -eq $help -or [string]::IsNullOrWhiteSpace($help.Synopsis)) { "$label : ヘルプ（.SYNOPSIS）が無い" }
                Get-HelpMismatch -HelpContent $help -ParamBlock $function.Body.ParamBlock -Label $label -RequireComplete
            }
        }

        (@($violations) -join "`n") | Should -BeNullOrEmpty
    }

    It "公開する関数には .SYNOPSIS と .EXAMPLE がある" {
        # PowerShell Gallery から入れた人が最初に読むのは Get-Help の使用例
        $violations = foreach ($file in Get-PublicSourceFile) {
            foreach ($function in (Get-FileAst -Path $file.FullName).FindAll($script:functionAstFilter, $false)) {
                $help = $function.GetHelpContent()
                if ($null -eq $help -or [string]::IsNullOrWhiteSpace($help.Synopsis)) { "$($function.Name) : .SYNOPSIS が無い" }
                if ($null -eq $help -or @($help.Examples).Count -eq 0) { "$($function.Name) : .EXAMPLE が無い" }
            }
        }

        (@($violations) -join "`n") | Should -BeNullOrEmpty
    }

    It "検査対象が 0 件になっていない" {
        # 対象の取り方を壊すと、この Describe が無条件に通る
        @(Get-PublicSourceFile).Count | Should -BeExactly 3
        @(Get-RepositoryScriptFile).Count | Should -BeGreaterThan 30
    }
}
