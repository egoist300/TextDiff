# TextDiff モジュールのマニフェスト。コードは書かず、データだけを持つ。
@{
    RootModule           = 'TextDiff.psm1'

    # 版の上げ方は CLAUDE.md の「Versioning」。PowerShell Gallery に一度公開した版は上書きできない
    ModuleVersion        = '1.0.0'

    GUID                 = '38718329-ae50-404c-84c4-0737d396dc3e'
    Author               = 'egoist300'
    Copyright            = '(c) 2026 egoist300. MIT License.'
    Description          = '2 つの行の並びを Myers 法で対応づけ、行内で変わった部分まで求めて、コンソール表示用の行と、左右に並べた 1 ファイル完結の HTML に変換する。出力の文言は日本語。'

    # 動作を確かめているのは Windows PowerShell 5.1 だけなので、Desktop だけを宣言する
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop')

    # ワイルドカードは使わない。Private に関数を足しただけで公開範囲が広がるため。
    # Public フォルダとの一致は tests\TextDiff.Module.Tests.ps1 が検査する
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
