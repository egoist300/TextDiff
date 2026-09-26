#Requires -Version 5.1

# Get-DiffHtmlScript のテスト。

BeforeAll {
    # テストのコード自身も StrictMode 3.0 で実行する。モジュールの中は TextDiff.psm1 が設定する。
    Set-StrictMode -Version 3.0
    # テスト対象はモジュールとして読み込み、テストはモジュールの中（InModuleScope）で実行する。
    # 非公開の関数はモジュールの中からしか呼び出せない。ファイルごとに読み込み直すため、前のファイルが定義した関数は残らない。
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\TextDiff\TextDiff.psd1') -Force
}

Describe "Get-DiffHtmlScript" {

    It "スクリプトは外部ファイルを読み込まない" {
        InModuleScope TextDiff {
            # src= で外部を参照すると、証跡を別のマシンにコピーした時点で動作しなくなるため。
            $script = Get-DiffHtmlScript

            $script | Should -Not -MatchExactly 'src\s*='
            $script | Should -MatchExactly 'scroll'
        }
    }

}

AfterAll {
    Remove-Module -Name TextDiff -ErrorAction SilentlyContinue
}
