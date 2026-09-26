#
# PSScriptAnalyzer 設定
#
#   Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
#
# VS Code の PowerShell 拡張は、ワークスペース直下のこのファイル名を自動で拾う。
# 除外したルールには理由を必ず添えること。理由の無い除外は、次に見た人が
# 「消してよいノイズ」と「消してはいけない指摘」を区別できなくなる。
#

@{
    # ParseError を必ず含めること。これは Error とは別のレベルで、書き忘れると
    # 構文エラーのあるファイルを検出 0 件として通す。
    # Information を落とすのは、PSUseOutputTypeCorrectly が `return @(...)` に対して解消できない
    # 検出を出すため。配列リテラルの実行時の型は中身によらず Object[] になるので、
    # [OutputType([hashtable[]])] と宣言しても残る。宣言してある型が契約として正しい
    Severity = @('ParseError', 'Error', 'Warning')

    Rules = @{
        PSUseSingularNouns = @{
            Enable = $true
        }
        # Windows PowerShell 5.1 で動かないが、PowerShell 7 では動く構文（&& や ?? など）を検出する
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
