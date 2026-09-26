#Requires -Version 5.1

# Get-DiffHtmlPane のテスト。

BeforeAll {
    # テストのコード自身も StrictMode 3.0 で実行する。モジュールの中は TextDiff.psm1 が設定する。
    Set-StrictMode -Version 3.0
    # テスト対象はモジュールとして読み込み、テストはモジュールの中（InModuleScope）で実行する。
    # 非公開の関数はモジュールの中からしか呼び出せない。ファイルごとに読み込み直すため、前のファイルが定義した関数は残らない。
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\TextDiff\TextDiff.psd1') -Force
}

Describe "Get-DiffHtmlPane" {

    # HTML ファイルを別のマシンにコピーしても表示が崩れないことが要件のため、
    # 外部を参照しないこと（CSS も JavaScript も埋め込む）を部品ごとに確認する。
    # 結合後の ConvertTo-DiffHtml だけを確認すると、どの部品が原因かが分からないため。

    It "ペインは左右で別のクラスになる" {
        InModuleScope TextDiff {
            # 左右が同じだと、横スクロールの同期が片側にしか適用されないため。
            $rows = @(Get-DiffAlignment -BeforeLines @('a') -AfterLines @('b'))

            $left = Get-DiffHtmlPane -Rows $rows -Side 'left'
            $right = Get-DiffHtmlPane -Rows $rows -Side 'right'

            $left | Should -Not -BeExactly $right
        }
    }

    It "ペインは指定した側の内容を出力する" {
        InModuleScope TextDiff {
            $rows = @(Get-DiffAlignment -BeforeLines @('alpha') -AfterLines @('beta'))

            (Get-DiffHtmlPane -Rows $rows -Side 'left') | Should -MatchExactly 'alpha'
            (Get-DiffHtmlPane -Rows $rows -Side 'right') | Should -MatchExactly 'beta'
        }
    }

    It "行が無くてもペインを生成できる" {
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
