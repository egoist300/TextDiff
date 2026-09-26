#Requires -Version 5.1

# Split-DiffToken のテスト。

BeforeAll {
    # テストのコード自身も StrictMode 3.0 で実行する。モジュールの中は TextDiff.psm1 が設定する。
    Set-StrictMode -Version 3.0
    # テスト対象はモジュールとして読み込み、テストはモジュールの中（InModuleScope）で実行する。
    # 非公開の関数はモジュールの中からしか呼び出せない。ファイルごとに読み込み直すため、前のファイルが定義した関数は残らない。
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\TextDiff\TextDiff.psd1') -Force
}

Describe "Split-DiffToken" {

    It "英数字の連続を 1 つのトークンにする" {
        InModuleScope TextDiff {
            Split-DiffToken -Text 'abc123' | Should -BeExactly @('abc123')
        }
    }

    It "記号は 1 文字ずつのトークンにする" {
        InModuleScope TextDiff {
            # 括弧やカンマをまたぐ変更を、その部分だけ示せるようにするため。
            Split-DiffToken -Text 'varying(100),' | Should -BeExactly @('varying', '(', '100', ')', ',')
        }
    }

    It "アンダースコアは語の一部として扱う" {
        InModuleScope TextDiff {
            # 識別子は snake_case が多い。display_name が分割されると、強調が読みにくくなるため。
            Split-DiffToken -Text 'display_name' | Should -BeExactly @('display_name')
        }
    }

    It "日本語は 1 文字ずつのトークンになる" {
        InModuleScope TextDiff {
            # 日本語は 1 文字の情報量が大きいため、1 文字単位の粒度で十分。
            Split-DiffToken -Text '給与' | Should -BeExactly @('給', '与')
        }
    }

    It "連結すると元の文字列と一致する" {
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
