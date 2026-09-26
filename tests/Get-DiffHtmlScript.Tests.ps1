#Requires -Version 5.1

# Get-DiffHtmlScript のテスト。

BeforeAll {
    # テストのコード自身も StrictMode 3.0 で動かす。モジュールの中は TextDiff.psm1 が設定している
    Set-StrictMode -Version 3.0
    # テスト対象はモジュールとして読み込み、テストの中身はモジュールの中（InModuleScope）で動かす。
    # 非公開の関数はモジュールの中からしか呼べない。ファイルごとに読み直すので、前のファイルが置いた関数は残らない
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\TextDiff\TextDiff.psd1') -Force
}

Describe "Get-DiffHtmlScript" {

    It "スクリプトは外部ファイルを読み込まない" {
        InModuleScope TextDiff {
            # src= で外部を参照すると、証跡を別マシンにコピーした時点で動かなくなる
            $script = Get-DiffHtmlScript

            $script | Should -Not -MatchExactly 'src\s*='
            $script | Should -MatchExactly 'scroll'
        }
    }

}

AfterAll {
    Remove-Module -Name TextDiff -ErrorAction SilentlyContinue
}
