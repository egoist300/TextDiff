#Requires -Version 5.1

# Get-DiffHtmlStyle のテスト。

BeforeAll {
    # テストのコード自身も StrictMode 3.0 で実行する。モジュールの中は TextDiff.psm1 が設定する。
    Set-StrictMode -Version 3.0
    # テスト対象はモジュールとして読み込み、テストはモジュールの中（InModuleScope）で実行する。
    # 非公開の関数はモジュールの中からしか呼び出せない。ファイルごとに読み込み直すため、前のファイルが定義した関数は残らない。
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

    It "ページの幅に上限を設けず、ウィンドウの幅いっぱいに表示する" {
        InModuleScope TextDiff {
            # 行を折り返さないため、上限があると広い画面でも長い行が横スクロールになる。
            Get-DiffHtmlStyle | Should -Not -MatchExactly '\.wrap\s*\{[^}]*max-width'
        }
    }

    It "スタイルは変更箇所の強調の色を定義する" {
        InModuleScope TextDiff {
            # 変更箇所を示すオレンジ。
            Get-DiffHtmlStyle | Should -Not -BeNullOrEmpty
        }
    }
}

AfterAll {
    Remove-Module -Name TextDiff -ErrorAction SilentlyContinue
}
