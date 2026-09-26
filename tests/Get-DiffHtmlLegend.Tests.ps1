#Requires -Version 5.1

# Get-DiffHtmlLegend のテスト。

BeforeAll {
    # テストのコード自身も StrictMode 3.0 で実行する。モジュールの中は TextDiff.psm1 が設定する。
    Set-StrictMode -Version 3.0
    # テスト対象はモジュールとして読み込み、テストはモジュールの中（InModuleScope）で実行する。
    # 非公開の関数はモジュールの中からしか呼び出せない。ファイルごとに読み込み直すため、前のファイルが定義した関数は残らない。
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\TextDiff\TextDiff.psd1') -Force
}

Describe "Get-DiffHtmlLegend" {

    It "凡例は配色の意味を文字でも示す" {
        InModuleScope TextDiff {
            # 色の区別がしにくい環境でも読めるようにするため。
            $legend = Get-DiffHtmlLegend

            $legend | Should -Not -BeNullOrEmpty
            $legend | Should -MatchExactly '削除|追加'
        }
    }

}

AfterAll {
    Remove-Module -Name TextDiff -ErrorAction SilentlyContinue
}
