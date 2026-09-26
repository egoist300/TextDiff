@{
    # 相対パスは、この設定ファイルの場所ではなく、実行時のカレントフォルダから解決される。リポジトリの直下で実行する前提。
    CustomRulePath      = @('tools\PSScriptAnalyzerRules\CodingRules.psm1')
    # CustomRulePath を指定すると、この設定が無い限り、既定のルールが警告なしに無効になる。
    IncludeDefaultRules = $true

    Rules = @{
        PSUseSingularNouns = @{
            Enable = $true
        }
        # PowerShell 7 では動作するが、Windows PowerShell 5.1 では動作しない構文（&& や ?? など）を検出する。
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('5.1')
        }
        PSPlaceOpenBrace = @{
            Enable             = $true
            OnSameLine         = $true
            NewLineAfter       = $true
            IgnoreOneLineBlock = $true
        }
        PSPlaceCloseBrace = @{
            Enable             = $true
            NewLineAfter       = $true
            IgnoreOneLineBlock = $true
        }
        PSUseConsistentIndentation = @{
            Enable          = $true
            Kind            = 'space'
            IndentationSize = 4
        }
        PSUseConsistentWhitespace = @{
            Enable         = $true
            CheckOpenBrace = $true
            CheckOpenParen = $true
            CheckOperator  = $false
            CheckSeparator = $true
        }
    }
}
