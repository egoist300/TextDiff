#Requires -Version 5.1

# tools/PSScriptAnalyzerRules/CodingRules.psm1（書き方の決まりのカスタムルール）のテスト。
#
# 決まりそのものの検査は PSScriptAnalyzer が行う（CI の lint ジョブと、VS Code の PowerShell 拡張）。
# ここでは、各ルールが違反を見つけ、決まりを守った書き方は見逃すことを確かめる。
# ルールが壊れて何も見つけなくなると、リポジトリ全体の検査が無条件に通るため。
#
# 各ルールには、違反の行と守った行を並べた短いスクリプトを渡し、指摘の出た行番号を比べる。
# スクリプトはファイルに書いて -Path で渡す。-ScriptDefinition で渡すと、同じ指摘が 2 回ずつ返る。

BeforeAll {
    Set-StrictMode -Version 3.0
    Import-Module -Name PSScriptAnalyzer -RequiredVersion 1.25.0
    $script:repoRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..')).Path
    $script:rulePath = Join-Path -Path $script:repoRoot -ChildPath 'tools\PSScriptAnalyzerRules\CodingRules.psm1'

    function script:Get-FindingLine {
        <#
        .SYNOPSIS
            1 つのルールだけを動かし、指摘の出た行番号を返す。
        .PARAMETER Rule
            ルール名（Measure- を除いた部分）。
        .PARAMETER Line
            検査させるスクリプトの行。
        #>
        param(
            [Parameter(Mandatory)] [string]$Rule,
            [Parameter(Mandatory)] [AllowEmptyString()] [string[]]$Line
        )
        $probePath = Join-Path -Path $TestDrive -ChildPath "$Rule.ps1"
        [System.IO.File]::WriteAllText($probePath, ($Line -join "`n") + "`n", [System.Text.UTF8Encoding]::new($true))
        $findings = @(Invoke-ScriptAnalyzer -Path $probePath -CustomRulePath $script:rulePath -IncludeRule "Measure-$Rule")
        return @($findings | ForEach-Object -Process { $_.Line })
    }
}

Describe "設定ファイル" {

    It "カスタムルールと既定のルールの両方を読み込む" {
        # 読み込みに失敗すると、指摘が 0 件のまま黙って通る。
        # 相対パスはカレントフォルダから解決されるので、CI と同じくリポジトリの直下で動かす
        $probePath = Join-Path -Path $TestDrive -ChildPath 'settings-probe.ps1'
        [System.IO.File]::WriteAllText($probePath, "`$left -eq `$right`ngci`n", [System.Text.UTF8Encoding]::new($true))
        Push-Location -LiteralPath $script:repoRoot
        try {
            $ruleNames = @(Invoke-ScriptAnalyzer -Path $probePath -Settings .\PSScriptAnalyzerSettings.psd1 | ForEach-Object -Process { $_.RuleName })
        }
        finally {
            Pop-Location
        }

        ($ruleNames -ccontains 'ImplicitCaseComparison') | Should -BeTrue
        ($ruleNames -ccontains 'PSAvoidUsingCmdletAliases') | Should -BeTrue
    }
}

Describe "カスタムルール" {

    It "AvoidLineContinuation: バッククォートの行継続を見つける" {
        Get-FindingLine -Rule AvoidLineContinuation -Line @(
            'Get-Item -Path x `'
            '    -Force'
            '$splat = @{ Path = ''x'' }'
            'Get-Item @splat'
        ) | Should -BeExactly @(1)
    }

    It "AvoidSingleLetterVariable: 1 文字の変数を見つけ、自動変数は見逃す" {
        Get-FindingLine -Rule AvoidSingleLetterVariable -Line @(
            '$p = 1'
            '$name = 1'
            '$items | ForEach-Object -Process { $_ }'
        ) | Should -BeExactly @(1)
    }

    It "AvoidBoolParameter: [bool] の引数を見つけ、[switch] は見逃す" {
        Get-FindingLine -Rule AvoidBoolParameter -Line @(
            'function Test-Flag { param([bool]$Flag) }'
            'function Test-Switch { param([switch]$Flag) }'
        ) | Should -BeExactly @(1)
    }

    It "AvoidPositionalArgument: 位置で渡した引数を見つける" {
        Get-FindingLine -Rule AvoidPositionalArgument -Line @(
            'function Test-Probe { param([string]$Key, [switch]$Flag, [string]$Other) }'
            'Test-Probe -Flag positional'
            'Test-Probe -Key named -Other named'
            'Join-Path $left $right'
            'Join-Path -Path $left -ChildPath $right'
            'powershell.exe -NoProfile -Command "1"'
            'It "name" { }'
        ) | Should -BeExactly @(2, 4, 4)
    }

    It "AvoidPositionalArgument: TextDiff の非公開の関数の引数も引く" {
        # テストは InModuleScope の中で非公開の関数を呼ぶ。Get-Command では引けないので、ソースから読む
        Get-FindingLine -Rule AvoidPositionalArgument -Line @(
            'Get-LineSimilarity $left $right'
            'Get-LineSimilarity -Left $left -Right $right'
        ) | Should -BeExactly @(1, 1)
    }

    It "FormatOperatorInMethodArgument: 括弧の無い -f を見つける" {
        Get-FindingLine -Rule FormatOperatorInMethodArgument -Line @(
            '$list.Add("{0} {1}" -f $first, $second)'
            '$list.Add(("{0} {1}" -f $first, $second))'
        ) | Should -BeExactly @(1)
    }

    It "AvoidStartProcess: Start-Process を見つける" {
        Get-FindingLine -Rule AvoidStartProcess -Line @(
            'Start-Process -FilePath powershell.exe'
            '& powershell.exe -NoProfile -Command "1"'
        ) | Should -BeExactly @(1)
    }

    It "StandaloneScriptHeader: #Requires とヘルプの無いスクリプトを見つける" {
        # param() が 3 行目にあるので、#Requires とヘルプが無いという指摘は 3 行目に出る
        Get-FindingLine -Rule StandaloneScriptHeader -Line @(
            '# 説明だけ'
            ''
            'param([string]$Name)'
        ) | Should -BeExactly @(3, 3)
    }

    It "StandaloneScriptHeader: 決まりどおりのスクリプトは見逃す" {
        Get-FindingLine -Rule StandaloneScriptHeader -Line @(
            '#Requires -Version 5.1'
            ''
            '<#'
            '.SYNOPSIS'
            '    例。'
            '.PARAMETER Name'
            '    名前。'
            '#>'
            'param([string]$Name)'
        ) | Should -BeNullOrEmpty
    }

    It "ImplicitCaseComparison: c も i も付けていない比較を見つける" {
        Get-FindingLine -Rule ImplicitCaseComparison -Line @(
            '$name -eq ''prd'''
            '$count -eq 0'
            '$name -ceq ''prd'''
            '$hostName -ieq $other'
            '$left -eq $right'
            '$list -contains ''a'''
            '$null -eq $value'
        ) | Should -BeExactly @(1, 5, 6)
    }

    It "InexactShouldOperator: 大小文字を区別しない Should の比較を見つける" {
        Get-FindingLine -Rule InexactShouldOperator -Line @(
            '$value | Should -Be ''x'''
            '$value | Should -BeExactly ''x'''
            '$list | Should -Contain ''x'''
            '($list -ccontains ''x'') | Should -BeTrue'
            '{ throw ''x'' } | Should -Throw ''x'''
            '{ throw ''x'' } | Should -Throw -ExpectedMessage ''x'''
            '{ throw ''x'' } | Should -Throw'
            '{ } | Should -Not -Throw'
            '{ throw ''x'' } | Should -Throw -ExceptionType ([System.ArgumentException])'
        ) | Should -BeExactly @(1, 3, 5, 6)
    }
}
