# 書き方の決まり（~/.claude/rules/powershell.md）を、PSScriptAnalyzer のカスタムルールとして検査する。
#
# PSScriptAnalyzerSettings.psd1 の CustomRulePath から読み込まれる。CI の lint ジョブと、
# VS Code の PowerShell 拡張（ワークスペース直下の設定ファイルを自動で拾う）の両方で動くため、
# 書いている最中に警告が出る。ルールそのものが違反を見つけられることは tests/CodingRules.Tests.ps1 が確かめる。
#
# 【PowerShell 自身の名前は、大小文字を区別せずに比べる】
# コマンド名・引数名・型名・変数名は、PowerShell が大小文字を区別しない。sort-object も
# Sort-Object として動くので、ここでの照合は -ieq / -icontains で書く。
#
# 【ルールはファイル全体に対して 1 回だけ調べる】
# ScriptBlockAst を受け取るルールは、入れ子のスクリプトブロックごとにも呼ばれる。
# 毎回すべてを調べると同じ指摘が重複するため、親の無いブロック（ファイル全体）のときだけ調べる。

Set-StrictMode -Version 3.0

# Pester の構文。テストの書き方そのもので、名前付きにすると読めなくなるため位置指定を許す
$script:PesterDsl = @('Describe', 'Context', 'It', 'BeforeAll', 'AfterAll', 'BeforeEach', 'AfterEach', 'BeforeDiscovery', 'Should', 'Mock', 'InModuleScope')

# 引数の一覧を覚えておく表は、AppDomain（同じプロセスの中で共有される領域）に置く。
# PSScriptAnalyzer はファイルごとに新しい runspace を作ってこのモジュールを読み込み直すため、
# モジュールの変数に置くとファイルごとに捨てられ、モジュールのソースを毎回解析し直すことになる。
# runspace は並行して動くことがあるので ConcurrentDictionary にする
$script:SharedCacheKey = 'TextDiff.CodingRules.CommandParameterCache'
$script:ModuleCacheKey = 'TextDiff.CodingRules.ModuleFunctionCache'

function ConvertTo-DiagnosticRecord {
    <#
    .SYNOPSIS
        ルールの指摘を、PSScriptAnalyzer が受け取る DiagnosticRecord にする。
    .PARAMETER RuleName
        ルール名（Measure- を除いた部分）。
    .PARAMETER Message
        指摘の文言。
    .PARAMETER Extent
        指摘する位置。
    #>
    param(
        [Parameter(Mandatory)] [string]$RuleName,
        [Parameter(Mandatory)] [string]$Message,
        [Parameter(Mandatory)] [System.Management.Automation.Language.IScriptExtent]$Extent
    )
    return [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord]@{
        RuleName = $RuleName
        Message  = $Message
        Extent   = $Extent
        Severity = 'Warning'
    }
}

function Find-Node {
    <#
    .SYNOPSIS
        構文木から、指定した型の節をすべて返す。
    .DESCRIPTION
        呼び出しをまたいで振り分け結果を使い回すと、リポジトリ全体にかけたときに別のファイルの節が
        返ってきた（並行して動くルールの呼び出しどうしで干渉したと考えられる）。
        呼び出しをまたいで持つのは、スレッドをまたいでも安全な AppDomain の表だけにする。
    .PARAMETER Ast
        探す範囲の構文木。
    .PARAMETER Type
        探す節の型。
    #>
    param(
        [Parameter(Mandatory)] [System.Management.Automation.Language.Ast]$Ast,
        [Parameter(Mandatory)] [type]$Type
    )
    $found = [System.Collections.Generic.List[object]]::new()
    foreach ($node in $Ast.FindAll({ $true }, $true)) {
        if ($Type.IsInstanceOfType($node)) { $found.Add($node) }
    }
    # ばらして返す。呼び出し側は foreach か @() で受ける（, を付けると @() が「配列を 1 つ持つ配列」になる）
    return $found.ToArray()
}

function Test-FileRoot {
    <#
    .SYNOPSIS
        スクリプトブロックがファイル全体（親の無いブロック）かを返す。
    .PARAMETER ScriptBlockAst
        調べるスクリプトブロック。
    #>
    param([Parameter(Mandatory)] [System.Management.Automation.Language.ScriptBlockAst]$ScriptBlockAst)
    return $null -eq $ScriptBlockAst.Parent
}

function ConvertFrom-FunctionDefinition {
    <#
    .SYNOPSIS
        関数定義の引数を、{ Name; Aliases; IsSwitch } の並びにする。
    .PARAMETER Definition
        関数定義の構文木。
    #>
    param([Parameter(Mandatory)] [System.Management.Automation.Language.FunctionDefinitionAst]$Definition)
    $parameterAsts = @()
    if ($null -ne $Definition.Body.ParamBlock) { $parameterAsts = @($Definition.Body.ParamBlock.Parameters) }
    elseif ($null -ne $Definition.Parameters) { $parameterAsts = @($Definition.Parameters) }
    foreach ($parameterAst in $parameterAsts) {
        $isSwitch = $false
        $aliases = [System.Collections.Generic.List[string]]::new()
        foreach ($attribute in $parameterAst.Attributes) {
            if ($attribute -is [System.Management.Automation.Language.TypeConstraintAst] -and $attribute.TypeName.Name -ieq 'switch') { $isSwitch = $true }
            if ($attribute -is [System.Management.Automation.Language.AttributeAst] -and $attribute.TypeName.Name -ieq 'Alias') {
                foreach ($aliasArgument in $attribute.PositionalArguments) { $aliases.Add($aliasArgument.Value) }
            }
        }
        [PSCustomObject]@{ Name = $parameterAst.Name.VariablePath.UserPath; Aliases = $aliases.ToArray(); IsSwitch = $isSwitch }
    }
}

function Get-FunctionNameWithoutScope {
    <#
    .SYNOPSIS
        関数名から script: などのスコープ修飾を外す。
    .PARAMETER Name
        関数定義に書かれた名前。
    #>
    param([Parameter(Mandatory)] [string]$Name)
    return ($Name -ireplace '^(script|global|local):', '')
}

function Get-SharedCommandTable {
    <#
    .SYNOPSIS
        Get-Command で引いたコマンド（コマンドレットなど）の引数の一覧を覚えておく表を返す。
    .DESCRIPTION
        コマンドの引数はプロセスが続く限り変わらないので、プロセスの中で 1 つの表を共有する。
        コマンド名は大小文字を区別しないので、表もそれに合わせる。
    #>
    $table = [System.AppDomain]::CurrentDomain.GetData($script:SharedCacheKey)
    if ($null -eq $table) {
        $table = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
        [System.AppDomain]::CurrentDomain.SetData($script:SharedCacheKey, $table)
    }
    return , $table
}

function Get-ModuleFunctionTable {
    <#
    .SYNOPSIS
        TextDiff モジュールの関数（非公開を含む）の引数を、ソースの構文木から読んだ表を返す。
    .DESCRIPTION
        テストは InModuleScope の中で非公開の関数を呼ぶため、Get-Command では引けない。
        VS Code で編集している間に引数が変わりうるので、ソースの更新時刻が変わったら読み直す。
    #>
    $moduleRoot = Join-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -ChildPath 'TextDiff'
    $emptyTable = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if (-not (Test-Path -LiteralPath $moduleRoot -PathType Container)) { return , $emptyTable }
    $files = @(Get-ChildItem -LiteralPath $moduleRoot -Recurse -File -Filter '*.ps1')
    $signature = '{0}:{1}' -f $files.Count, (@($files | ForEach-Object -Process { $_.LastWriteTimeUtc.Ticks } | Measure-Object -Maximum).Maximum)

    $cached = [System.AppDomain]::CurrentDomain.GetData($script:ModuleCacheKey)
    if ($null -ne $cached -and $cached.Signature -ceq $signature) { return , $cached.Table }

    $table = $emptyTable
    foreach ($file in $files) {
        $fileAst = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)
        foreach ($definition in (Find-Node -Ast $fileAst -Type ([System.Management.Automation.Language.FunctionDefinitionAst]))) {
            $table[(Get-FunctionNameWithoutScope -Name $definition.Name)] = @(ConvertFrom-FunctionDefinition -Definition $definition)
        }
    }
    [System.AppDomain]::CurrentDomain.SetData($script:ModuleCacheKey, [PSCustomObject]@{ Signature = $signature; Table = $table })
    return , $table
}

function Get-CommandParameterList {
    <#
    .SYNOPSIS
        コマンド名から、その引数の一覧を返す。ネイティブコマンドは $null、見つからなければ空の一覧。
    .PARAMETER Name
        コマンド名。
    .PARAMETER LocalFunction
        検査しているファイルの中で定義された関数の引数の表（関数名 → 引数の一覧）。
    .PARAMETER ModuleFunction
        Get-ModuleFunctionTable が返す、モジュールの関数の引数の表。
    #>
    param(
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [System.Collections.Generic.Dictionary[string, object]]$LocalFunction,
        [Parameter(Mandatory)] [System.Collections.Concurrent.ConcurrentDictionary[string, object]]$ModuleFunction
    )
    if ($LocalFunction.ContainsKey($Name)) { return , $LocalFunction[$Name] }
    if ($ModuleFunction.ContainsKey($Name)) { return , $ModuleFunction[$Name] }
    $commandTable = Get-SharedCommandTable
    if (-not $commandTable.ContainsKey($Name)) {
        $command = Get-Command -Name $Name -ErrorAction SilentlyContinue | Select-Object -First 1
        $commandTable[$Name] = if ($null -eq $command) { @() }
        elseif ($command -is [System.Management.Automation.ApplicationInfo]) { $null }
        else {
            @($command.Parameters.Values | ForEach-Object -Process {
                    [PSCustomObject]@{ Name = $_.Name; Aliases = @($_.Aliases); IsSwitch = $_.SwitchParameter }
                })
        }
    }
    return , $commandTable[$Name]
}

function Find-Parameter {
    <#
    .SYNOPSIS
        引数の一覧から、名前・別名・一意に決まる前方一致の省略形で引数を探す。見つからなければ $null。
    .PARAMETER ParameterList
        Get-CommandParameterList が返す引数の一覧。
    .PARAMETER Name
        コマンドに書かれた引数名（- を除く）。
    #>
    param(
        [AllowNull()] [AllowEmptyCollection()] [object[]]$ParameterList,
        [Parameter(Mandatory)] [string]$Name
    )
    $exact = @($ParameterList | Where-Object -FilterScript { $_.Name -ieq $Name -or $_.Aliases -icontains $Name })
    if ($exact.Count -gt 0) { return $exact[0] }
    $prefixed = @($ParameterList | Where-Object -FilterScript { $_.Name.StartsWith($Name, [System.StringComparison]::OrdinalIgnoreCase) })
    if ($prefixed.Count -eq 1) { return $prefixed[0] }
    return $null
}

function Test-NonStringOperand {
    <#
    .SYNOPSIS
        式が文字列になりえない定数（数値、$null、$true、$false）かを返す。
    .DESCRIPTION
        これと比べる -eq / -ne は大小文字の扱いを持たないので、c も i も要らない。
    .PARAMETER Operand
        比較演算子の片側の式。
    #>
    param([Parameter(Mandatory)] [System.Management.Automation.Language.Ast]$Operand)
    if ($Operand -is [System.Management.Automation.Language.ConstantExpressionAst] -and
        $Operand -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) { return $true }
    return ($Operand -is [System.Management.Automation.Language.VariableExpressionAst] -and
        @('null', 'true', 'false') -icontains $Operand.VariablePath.UserPath)
}

function Measure-AvoidLineContinuation {
    <#
    .SYNOPSIS
        バッククォート（`）で行を継続していないかを調べる。
    .DESCRIPTION
        行末に空白が 1 つ入るだけで継続が切れ、次の行が別の文になります。
        長い呼び出しはスプラッティングか、演算子やパイプでの自然な改行にします。
    .PARAMETER Token
        ファイルのトークン。PSScriptAnalyzer が渡します。
    .OUTPUTS
        [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]]
    #>
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param([Parameter(Mandatory)] [System.Management.Automation.Language.Token[]]$Token)

    foreach ($item in $Token) {
        if ($item.Kind -ceq [System.Management.Automation.Language.TokenKind]::LineContinuation) {
            ConvertTo-DiagnosticRecord -RuleName 'AvoidLineContinuation' -Extent $item.Extent -Message 'バッククォートで行を継続しない。スプラッティングか自然な改行にする'
        }
    }
}

function Measure-AvoidSingleLetterVariable {
    <#
    .SYNOPSIS
        1 文字の変数名を使っていないかを調べる（$_ などの自動変数を除く）。
    .DESCRIPTION
        呼んだコマンドが、呼び出し元の同名の変数を上書きしえます（Invoke-Pester は $p を上書きする）。
        名前から役割も読めません。
    .PARAMETER ScriptBlockAst
        検査するスクリプト。PSScriptAnalyzer が渡します。
    .OUTPUTS
        [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]]
    #>
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param([Parameter(Mandatory)] [System.Management.Automation.Language.ScriptBlockAst]$ScriptBlockAst)

    if (-not (Test-FileRoot -ScriptBlockAst $ScriptBlockAst)) { return }
    foreach ($variable in (Find-Node -Ast $ScriptBlockAst -Type ([System.Management.Automation.Language.VariableExpressionAst]))) {
        $name = $variable.VariablePath.UserPath -ireplace '^(script|global|local|private|using):', ''
        if ($name.Length -eq 1 -and @('_', '?', '^', '$') -cnotcontains $name) {
            ConvertTo-DiagnosticRecord -RuleName 'AvoidSingleLetterVariable' -Extent $variable.Extent -Message "1 文字の変数名 `$$name を使わない。役割の分かる名前にする"
        }
    }
}

function Measure-AvoidBoolParameter {
    <#
    .SYNOPSIS
        [bool] の引数を作っていないかを調べる。
    .DESCRIPTION
        [bool] の引数は -Flag と書けず、-Flag:$true が要ります。[switch] を使います。
    .PARAMETER ScriptBlockAst
        検査するスクリプト。PSScriptAnalyzer が渡します。
    .OUTPUTS
        [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]]
    #>
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param([Parameter(Mandatory)] [System.Management.Automation.Language.ScriptBlockAst]$ScriptBlockAst)

    if (-not (Test-FileRoot -ScriptBlockAst $ScriptBlockAst)) { return }
    foreach ($parameter in (Find-Node -Ast $ScriptBlockAst -Type ([System.Management.Automation.Language.ParameterAst]))) {
        foreach ($attribute in $parameter.Attributes) {
            if ($attribute -is [System.Management.Automation.Language.TypeConstraintAst] -and
                @('bool', 'boolean', 'System.Boolean') -icontains $attribute.TypeName.FullName) {
                ConvertTo-DiagnosticRecord -RuleName 'AvoidBoolParameter' -Extent $parameter.Extent -Message "[bool] の引数 `$$($parameter.Name.VariablePath.UserPath) を作らない。[switch] にする"
            }
        }
    }
}

function Measure-AvoidPositionalArgument {
    <#
    .SYNOPSIS
        コマンドに引数を位置で渡していないかを調べる。
    .DESCRIPTION
        位置で渡すと、引数の並びが変わったときに黙って別の引数に入ります。
        Pester の構文（Describe / It / Should / Mock など）と、ネイティブコマンド（powershell.exe など）、
        & $変数 の呼び出しは対象外です。前者はテストの書き方そのもので、後者は PowerShell の
        引数ではないか、何が呼ばれるかを静的に決められないためです。
    .PARAMETER ScriptBlockAst
        検査するスクリプト。PSScriptAnalyzer が渡します。
    .OUTPUTS
        [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]]
    #>
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param([Parameter(Mandatory)] [System.Management.Automation.Language.ScriptBlockAst]$ScriptBlockAst)

    if (-not (Test-FileRoot -ScriptBlockAst $ScriptBlockAst)) { return }
    $moduleFunction = Get-ModuleFunctionTable
    $localFunction = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($definition in (Find-Node -Ast $ScriptBlockAst -Type ([System.Management.Automation.Language.FunctionDefinitionAst]))) {
        $localFunction[(Get-FunctionNameWithoutScope -Name $definition.Name)] = @(ConvertFrom-FunctionDefinition -Definition $definition)
    }

    foreach ($commandAst in (Find-Node -Ast $ScriptBlockAst -Type ([System.Management.Automation.Language.CommandAst]))) {
        $elements = $commandAst.CommandElements
        if ($elements[0] -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) { continue }
        $commandName = $commandAst.GetCommandName()
        if ($script:PesterDsl -icontains $commandName) { continue }
        if ($commandName -imatch '\.exe$') { continue }
        $parameterList = Get-CommandParameterList -Name $commandName -LocalFunction $localFunction -ModuleFunction $moduleFunction
        if ($null -eq $parameterList) { continue }

        # -名前 の直後の要素は、その引数がスイッチでなければ値として読み飛ばす
        for ($elementIndex = 1; $elementIndex -lt $elements.Count; $elementIndex++) {
            $element = $elements[$elementIndex]
            if ($element -is [System.Management.Automation.Language.CommandParameterAst]) {
                if ($null -ne $element.Argument) { continue }
                $parameter = Find-Parameter -ParameterList $parameterList -Name $element.ParameterName
                if ($null -ne $parameter -and $parameter.IsSwitch) { continue }
                $elementIndex++
                continue
            }
            if ($element -is [System.Management.Automation.Language.VariableExpressionAst] -and $element.Splatted) { continue }
            ConvertTo-DiagnosticRecord -RuleName 'AvoidPositionalArgument' -Extent $element.Extent -Message "$commandName に引数を位置で渡さない。-名前 を付ける"
        }
    }
}

function Measure-FormatOperatorInMethodArgument {
    <#
    .SYNOPSIS
        メソッドの引数に、括弧で囲まない -f を書いていないかを調べる。
    .DESCRIPTION
        囲まないと "{0} {1}" -f $first, $second の , がメソッドの引数の区切りになり、書式の値が欠けます。
    .PARAMETER ScriptBlockAst
        検査するスクリプト。PSScriptAnalyzer が渡します。
    .OUTPUTS
        [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]]
    #>
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param([Parameter(Mandatory)] [System.Management.Automation.Language.ScriptBlockAst]$ScriptBlockAst)

    if (-not (Test-FileRoot -ScriptBlockAst $ScriptBlockAst)) { return }
    foreach ($invocation in (Find-Node -Ast $ScriptBlockAst -Type ([System.Management.Automation.Language.InvokeMemberExpressionAst]))) {
        foreach ($argument in @($invocation.Arguments)) {
            if ($argument -is [System.Management.Automation.Language.BinaryExpressionAst] -and
                $argument.Operator -ceq [System.Management.Automation.Language.TokenKind]::Format) {
                ConvertTo-DiagnosticRecord -RuleName 'FormatOperatorInMethodArgument' -Extent $argument.Extent -Message 'メソッドの引数の -f は括弧で囲む'
            }
        }
    }
}

function Measure-AvoidStartProcess {
    <#
    .SYNOPSIS
        Start-Process でコンソールのプログラムを動かしていないかを調べる。
    .DESCRIPTION
        -ArgumentList は要素を引用せずに空白でつなぎ、-Wait が無いと ExitCode が空になります。
        & と $LASTEXITCODE か、ProcessStartInfo を使います。
    .PARAMETER ScriptBlockAst
        検査するスクリプト。PSScriptAnalyzer が渡します。
    .OUTPUTS
        [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]]
    #>
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param([Parameter(Mandatory)] [System.Management.Automation.Language.ScriptBlockAst]$ScriptBlockAst)

    if (-not (Test-FileRoot -ScriptBlockAst $ScriptBlockAst)) { return }
    foreach ($commandAst in (Find-Node -Ast $ScriptBlockAst -Type ([System.Management.Automation.Language.CommandAst]))) {
        if ($commandAst.GetCommandName() -ieq 'Start-Process') {
            ConvertTo-DiagnosticRecord -RuleName 'AvoidStartProcess' -Extent $commandAst.Extent -Message 'Start-Process でコンソールのプログラムを動かさない。& と $LASTEXITCODE か ProcessStartInfo を使う'
        }
    }
}

function Measure-StandaloneScriptHeader {
    <#
    .SYNOPSIS
        単独で実行するスクリプトが、#Requires -Version 5.1 と、すべての引数を書いたヘルプを持つかを調べる。
    .DESCRIPTION
        ファイル直下に param() を持つものを、単独で実行するスクリプトとみなします。
        tests\ の下は対象外です（Pester が読み込むテストで、単独では実行しない）。
        #Requires とヘルプの間に空行が無いと、Get-Help がヘルプを認識しません。
    .PARAMETER ScriptBlockAst
        検査するスクリプト。PSScriptAnalyzer が渡します。
    .OUTPUTS
        [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]]
    #>
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param([Parameter(Mandatory)] [System.Management.Automation.Language.ScriptBlockAst]$ScriptBlockAst)

    if (-not (Test-FileRoot -ScriptBlockAst $ScriptBlockAst)) { return }
    if ($null -eq $ScriptBlockAst.ParamBlock) { return }
    # Windows のパスは大小文字を区別しない
    $filePath = $ScriptBlockAst.Extent.File
    if ($filePath -and $filePath -imatch '[\\/]tests[\\/]') { return }

    $required = $ScriptBlockAst.ScriptRequirements
    if ($null -eq $required -or $required.RequiredPSVersion -cne [version]'5.1') {
        ConvertTo-DiagnosticRecord -RuleName 'StandaloneScriptHeader' -Extent $ScriptBlockAst.ParamBlock.Extent -Message '単独で実行するスクリプトは #Requires -Version 5.1 で始める'
    }
    $help = $ScriptBlockAst.GetHelpContent()
    if ($null -eq $help) {
        ConvertTo-DiagnosticRecord -RuleName 'StandaloneScriptHeader' -Extent $ScriptBlockAst.ParamBlock.Extent -Message 'ヘルプが認識されない。#Requires とヘルプの間に空行を入れる'
        return
    }
    # ヘルプは引数名の大小文字を保持しない
    $documented = @($help.Parameters.Keys)
    foreach ($parameter in $ScriptBlockAst.ParamBlock.Parameters) {
        $name = $parameter.Name.VariablePath.UserPath
        if ($documented -inotcontains $name) {
            ConvertTo-DiagnosticRecord -RuleName 'StandaloneScriptHeader' -Extent $parameter.Extent -Message ".PARAMETER $name がヘルプに無い"
        }
    }
}

function Measure-ImplicitCaseComparison {
    <#
    .SYNOPSIS
        大小文字の扱いを明示していない比較演算子を調べる。
    .DESCRIPTION
        PowerShell の比較演算子は既定で大小文字を区別しません。区別するものは -ceq のように c を、
        区別しないのが正しいもの（PowerShell 自身の名前、Windows のファイル名など）は -ieq のように i を付けます。
        -eq / -ne は数値や $null にも使うため、相手が数値・$null・真偽値の定数なら求めません。
    .PARAMETER ScriptBlockAst
        検査するスクリプト。PSScriptAnalyzer が渡します。
    .OUTPUTS
        [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]]
    #>
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param([Parameter(Mandatory)] [System.Management.Automation.Language.ScriptBlockAst]$ScriptBlockAst)

    if (-not (Test-FileRoot -ScriptBlockAst $ScriptBlockAst)) { return }
    $stringOperators = @('like', 'notlike', 'match', 'notmatch', 'replace', 'split', 'contains', 'notcontains', 'in', 'notin')
    $equalityOperators = @('eq', 'ne')
    foreach ($node in (Find-Node -Ast $ScriptBlockAst -Type ([System.Management.Automation.Language.BinaryExpressionAst]))) {
        $operatorName = $node.ErrorPosition.Text.TrimStart('-').ToLowerInvariant()
        $comparesNonString = (Test-NonStringOperand -Operand $node.Left) -or (Test-NonStringOperand -Operand $node.Right)
        $isImplicitEquality = ($equalityOperators -ccontains $operatorName) -and -not $comparesNonString
        if (($stringOperators -ccontains $operatorName) -or $isImplicitEquality) {
            ConvertTo-DiagnosticRecord -RuleName 'ImplicitCaseComparison' -Extent $node.ErrorPosition -Message "$($node.ErrorPosition.Text) は大小文字の扱いを明示する（-c$operatorName か -i$operatorName）"
        }
    }
}

function Measure-InexactShouldOperator {
    <#
    .SYNOPSIS
        大小文字を区別しない Should の比較を調べる。
    .DESCRIPTION
        -Be / -Match / -BeLike / -Contain / -BeIn と、-Throw のメッセージ照合は大小文字を区別せず、
        大小文字の不具合がテストをすり抜けます。-BeExactly / -MatchExactly / -BeLikeExactly を使います。
        -Contain / -BeIn は、-ccontains で比べた結果を Should -BeTrue で確かめます。
        -Throw は、メッセージではなく -ExceptionType か -ErrorId で確かめます。
        メッセージを照合しない -Throw と、-Not -Throw は対象外です。
    .PARAMETER ScriptBlockAst
        検査するスクリプト。PSScriptAnalyzer が渡します。
    .OUTPUTS
        [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]]
    #>
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param([Parameter(Mandatory)] [System.Management.Automation.Language.ScriptBlockAst]$ScriptBlockAst)

    if (-not (Test-FileRoot -ScriptBlockAst $ScriptBlockAst)) { return }
    $replacement = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $replacement['Be'] = '-BeExactly'
    $replacement['Match'] = '-MatchExactly'
    $replacement['BeLike'] = '-BeLikeExactly'
    $replacement['Contain'] = '-ccontains の結果を -BeTrue'
    $replacement['BeIn'] = '-ccontains の結果を -BeTrue'
    foreach ($commandAst in (Find-Node -Ast $ScriptBlockAst -Type ([System.Management.Automation.Language.CommandAst]))) {
        if ($commandAst.GetCommandName() -ine 'Should') { continue }
        $elements = @($commandAst.CommandElements)
        for ($elementIndex = 1; $elementIndex -lt $elements.Count; $elementIndex++) {
            $element = $elements[$elementIndex]
            if ($element -isnot [System.Management.Automation.Language.CommandParameterAst]) { continue }
            $name = $element.ParameterName
            if ($replacement.ContainsKey($name)) {
                ConvertTo-DiagnosticRecord -RuleName 'InexactShouldOperator' -Extent $element.Extent -Message "Should -$name は大小文字を区別しない。$($replacement[$name]) で確かめる"
                continue
            }
            if ($name -ine 'Throw') { continue }
            $hasPositionalMessage = $elementIndex + 1 -lt $elements.Count -and
            $elements[$elementIndex + 1] -isnot [System.Management.Automation.Language.CommandParameterAst]
            $hasNamedMessage = @($elements | Where-Object -FilterScript {
                    $_ -is [System.Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -ieq 'ExpectedMessage' }).Count -gt 0
            if ($hasPositionalMessage -or $hasNamedMessage) {
                ConvertTo-DiagnosticRecord -RuleName 'InexactShouldOperator' -Extent $element.Extent -Message 'Should -Throw のメッセージ照合は大小文字を区別しない。-ExceptionType か -ErrorId で確かめる'
            }
        }
    }
}

Export-ModuleMember -Function Measure-*
