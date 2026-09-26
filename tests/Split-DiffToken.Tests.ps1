# Split-DiffToken のテスト。

BeforeAll {
    # テストのコード自身も StrictMode 3.0 で動かす。モジュールの中は TextDiff.psm1 が設定している
    Set-StrictMode -Version 3.0
    # テスト対象はモジュールとして読み込み、テストの中身はモジュールの中（InModuleScope）で動かす。
    # 非公開の関数はモジュールの中からしか呼べない。ファイルごとに読み直すので、前のファイルが置いた関数は残らない
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\TextDiff\TextDiff.psd1') -Force
}

Describe "Split-DiffToken" {

    It "英数字の連続を1つのトークンにする" {
        InModuleScope TextDiff {
            Split-DiffToken -Text 'abc123' | Should -BeExactly @('abc123')
        }
    }

    It "記号は1文字ずつ独立したトークンにする" {
        InModuleScope TextDiff {
            # 括弧やカンマをまたいだ変更を、その部分だけ示せるようにするため
            Split-DiffToken -Text 'varying(100),' | Should -BeExactly @('varying', '(', '100', ')', ',')
        }
    }

    It "アンダースコアは語の一部として扱う" {
        InModuleScope TextDiff {
            # SQL の識別子は snake_case。display_name が分断されると強調が読めなくなる
            Split-DiffToken -Text 'display_name' | Should -BeExactly @('display_name')
        }
    }

    It "日本語は1文字ずつになる" {
        InModuleScope TextDiff {
            # 日本語は1文字の情報量が大きいので、この粒度が意図どおり
            Split-DiffToken -Text '給与' | Should -BeExactly @('給', '与')
        }
    }

    It "連結すると元の文字列に戻る" {
        InModuleScope TextDiff {
            $text = '  A001,1,SampleCode,2026-08-17,ops@example.com'

            (-join (Split-DiffToken -Text $text)) | Should -BeExactly $text
        }
    }

    It "空文字なら空の配列" {
        InModuleScope TextDiff {
            @(Split-DiffToken -Text '').Count | Should -BeExactly 0
        }
    }
}

AfterAll {
    Remove-Module -Name TextDiff -ErrorAction SilentlyContinue
}
