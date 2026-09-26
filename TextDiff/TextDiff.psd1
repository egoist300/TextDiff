@{
    RootModule           = 'TextDiff.psm1'

    ModuleVersion        = '1.0.0'

    GUID                 = '38718329-ae50-404c-84c4-0737d396dc3e'
    Author               = 'egoist300'
    Copyright            = '(c) 2026 egoist300. MIT License.'
    Description          = '変更前と変更後の 2 つの行の配列を比較して差分を算出し、コンソール表示用の行と、左右に並べて表示する HTML に変換する。HTML の見出しや凡例などの文言は日本語。'

    # 動作保証は Windows PowerShell 5.1 だけなので、Desktop のみを宣言する。
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop')

    FunctionsToExport    = @(
        'ConvertTo-DiffHtml'
        'ConvertTo-DiffText'
        'Get-DiffAlignment'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    PrivateData          = @{
        PSData = @{
            Tags       = @('Diff', 'Myers', 'SideBySide', 'Html', 'Japanese', 'Windows')
            LicenseUri = 'https://github.com/egoist300/TextDiff/blob/main/LICENSE'
            ProjectUri = 'https://github.com/egoist300/TextDiff'
        }
    }
}
