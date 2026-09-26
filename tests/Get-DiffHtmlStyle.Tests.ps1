#Requires -Version 5.1

# Get-DiffHtmlStyle のテスト。

BeforeAll {
    # テストのコード自身も StrictMode 3.0 で動かす。モジュールの中は TextDiff.psm1 が設定している
    Set-StrictMode -Version 3.0
    # テスト対象はモジュールとして読み込み、テストの中身はモジュールの中（InModuleScope）で動かす。
    # 非公開の関数はモジュールの中からしか呼べない。ファイルごとに読み直すので、前のファイルが置いた関数は残らない
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\TextDiff\TextDiff.psd1') -Force
}

Describe "Get-DiffHtmlStyle" {

    It "スタイルは外部ファイルを読み込まない" {
        InModuleScope TextDiff {
            $style = Get-DiffHtmlStyle

            $style | Should -Not -MatchExactly '@import'
            $style | Should -Not -MatchExactly 'href\s*='
        }
    }

    It "スタイルは行内強調の色を持つ" {
        InModuleScope TextDiff {
            # 桁だけが変わった行で、変わった部分を示すオレンジ
            Get-DiffHtmlStyle | Should -Not -BeNullOrEmpty
        }
    }
}

AfterAll {
    Remove-Module -Name TextDiff -ErrorAction SilentlyContinue
}
