#Requires -Version 5.1

# Get-DiffHtmlPane のテスト。

BeforeAll {
    # テストのコード自身も StrictMode 3.0 で動かす。モジュールの中は TextDiff.psm1 が設定している
    Set-StrictMode -Version 3.0
    # テスト対象はモジュールとして読み込み、テストの中身はモジュールの中（InModuleScope）で動かす。
    # 非公開の関数はモジュールの中からしか呼べない。ファイルごとに読み直すので、前のファイルが置いた関数は残らない
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\TextDiff\TextDiff.psd1') -Force
}

Describe "Get-DiffHtmlPane" {

    # 証跡フォルダごと別のマシンへコピーしても崩れないことが要件なので、
    # 外部への参照を作らないこと（CSS も JS も埋め込み）を断片ごとに固定する。
    # 合成後の ConvertTo-DiffHtml だけを見ていると、どの断片が原因かが分からない

    It "ペインは左右で別のクラスになる" {
        InModuleScope TextDiff {
            # 左右が同じだと横スクロールの同期が片側にしか効かない
            $rows = @(Get-DiffAlignment -BeforeLines @('a') -AfterLines @('b'))

            $left = Get-DiffHtmlPane -Rows $rows -Side 'left'
            $right = Get-DiffHtmlPane -Rows $rows -Side 'right'

            $left | Should -Not -BeExactly $right
        }
    }

    It "ペインは指定した側の内容を出す" {
        InModuleScope TextDiff {
            $rows = @(Get-DiffAlignment -BeforeLines @('alpha') -AfterLines @('beta'))

            (Get-DiffHtmlPane -Rows $rows -Side 'left') | Should -MatchExactly 'alpha'
            (Get-DiffHtmlPane -Rows $rows -Side 'right') | Should -MatchExactly 'beta'
        }
    }

    It "行が無くてもペインを組み立てられる" {
        InModuleScope TextDiff {
            { Get-DiffHtmlPane -Rows @() -Side 'left' } | Should -Not -Throw
        }
    }

    It "左右以外の側は受け付けない" {
        InModuleScope TextDiff {
            { Get-DiffHtmlPane -Rows @() -Side 'center' } | Should -Throw
        }
    }

}

AfterAll {
    Remove-Module -Name TextDiff -ErrorAction SilentlyContinue
}
