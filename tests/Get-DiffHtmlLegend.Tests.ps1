# Get-DiffHtmlLegend のテスト。

BeforeAll {
    # テストのコード自身も StrictMode 3.0 で動かす。モジュールの中は TextDiff.psm1 が設定している
    Set-StrictMode -Version 3.0
    # テスト対象はモジュールとして読み込み、テストの中身はモジュールの中（InModuleScope）で動かす。
    # 非公開の関数はモジュールの中からしか呼べない。ファイルごとに読み直すので、前のファイルが置いた関数は残らない
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\TextDiff\TextDiff.psd1') -Force
}

Describe "Get-DiffHtmlLegend" {

    It "凡例は色の意味を文字でも示す" {
        InModuleScope TextDiff {
            # 色が見分けにくい環境でも読めるようにするため
            $legend = Get-DiffHtmlLegend

            $legend | Should -Not -BeNullOrEmpty
            $legend | Should -MatchExactly '削除|追加'
        }
    }

}

AfterAll {
    Remove-Module -Name TextDiff -ErrorAction SilentlyContinue
}
