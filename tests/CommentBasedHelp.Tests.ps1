# コメントベースヘルプが実装とずれていないかを機械で検査する。
#
# ヘルプはずれても lint もテストも落ちない。読む人はヘルプを信じるので、
# 書いていない引数は「無い」と受け取られる。
# 検査するのは対応関係だけで、説明文の中身は見ない。

BeforeAll {
    Set-StrictMode -Version 3.0
    $script:repoRoot = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')).Path

    # 公開する関数は Get-Help で読む人がいるので、引数の記載と使用例を必須にする。
    # 非公開の関数は、型で中身が分からない引数だけ必須にする（CLAUDE.md の「Comment-based help」）
    function Get-PublicSourceFile {
        Get-ChildItem -LiteralPath (Join-Path -Path $script:repoRoot -ChildPath 'TextDiff\Public') -Filter *.ps1 -File -ErrorAction Stop
    }

    function Get-PrivateSourceFile {
        Get-ChildItem -LiteralPath (Join-Path -Path $script:repoRoot -ChildPath 'TextDiff\Private') -Filter *.ps1 -File -ErrorAction Stop
    }

    function Get-FileAst {
        param([string]$Path)
        $tokens = $null
        $errors = $null
        return [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    }

    # ヘルプが記載しているパラメータ名と、実際の param() を突き合わせる。
    # 引数名は PowerShell の名前なので、大小文字を区別せずに比べる
    function Get-HelpMismatch {
        # RequireComplete: 実在する引数がすべて記載されていることまで求めるか
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

    It "公開する関数の .PARAMETER と param() が一致する" {
        $violations = foreach ($file in Get-PublicSourceFile) {
            foreach ($function in (Get-FileAst -Path $file.FullName).FindAll($script:functionAstFilter, $false)) {
                Get-HelpMismatch -HelpContent $function.GetHelpContent() -ParamBlock $function.Body.ParamBlock -Label "$($file.Name)/$($function.Name)" -RequireComplete
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

    It "非公開の関数は、実在しない引数を書いていない" {
        # 引数を消したのにヘルプだけ残ると、消えた理由を探す手間になる
        $violations = foreach ($file in Get-PrivateSourceFile) {
            foreach ($function in (Get-FileAst -Path $file.FullName).FindAll($script:functionAstFilter, $true)) {
                Get-HelpMismatch -HelpContent $function.GetHelpContent() -ParamBlock $function.Body.ParamBlock -Label "$($file.Name)/$($function.Name)"
            }
        }

        (@($violations) -join "`n") | Should -BeNullOrEmpty
    }

    It "非公開の関数は、型で中身が分からない引数を記載している" {
        # 名前と型と検証属性で伝わる引数には書かない。ただしハッシュテーブルや配列、型なしの引数は、
        # どんなキーや要素を持つのかが param() から読めないので書く。
        # 関数の中で定義した関数は見ない。呼び出しがすべて数行先にあり、たどる必要が無い
        $shapelessTypes = @('hashtable', 'PSCustomObject', 'psobject', 'array', 'object', 'object[]')
        $violations = foreach ($file in Get-PrivateSourceFile) {
            foreach ($function in (Get-FileAst -Path $file.FullName).FindAll($script:functionAstFilter, $false)) {
                if ($null -eq $function.Body.ParamBlock) { continue }
                $help = $function.GetHelpContent()
                $documented = @()
                if ($null -ne $help -and $null -ne $help.Parameters) { $documented = @($help.Parameters.Keys) }

                foreach ($parameter in $function.Body.ParamBlock.Parameters) {
                    $typeNames = @($parameter.Attributes |
                            Where-Object -FilterScript { $_ -is [System.Management.Automation.Language.TypeConstraintAst] } |
                            ForEach-Object -Process { $_.TypeName.FullName })
                    $shapelessTypeNames = @($typeNames | Where-Object -FilterScript { $shapelessTypes -icontains $_ })
                    if ($typeNames.Count -gt 0 -and $shapelessTypeNames.Count -eq 0) { continue }

                    $name = $parameter.Name.VariablePath.UserPath
                    if ($documented -inotcontains $name) { "$($file.Name)/$($function.Name) : '$name' の中身が書かれていない" }
                }
            }
        }

        (@($violations) -join "`n") | Should -BeNullOrEmpty
    }

    It "検査対象が 0 件になっていない" {
        # 対象の取り方を壊すと、この Describe が無条件に通る
        @(Get-PublicSourceFile).Count | Should -BeExactly 3
        @(Get-PrivateSourceFile).Count | Should -BeGreaterThan 10
    }
}
