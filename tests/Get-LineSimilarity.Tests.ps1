#Requires -Version 5.1

# Get-LineSimilarity のテスト。

BeforeAll {
    # テストのコード自身も StrictMode 3.0 で動かす。モジュールの中は TextDiff.psm1 が設定している
    Set-StrictMode -Version 3.0
    # テスト対象はモジュールとして読み込み、テストの中身はモジュールの中（InModuleScope）で動かす。
    # 非公開の関数はモジュールの中からしか呼べない。ファイルごとに読み直すので、前のファイルが置いた関数は残らない
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\TextDiff\TextDiff.psd1') -Force
}

Describe "Get-LineSimilarity" {

    It "完全に同じなら 1.0" {
        InModuleScope TextDiff {
            Get-LineSimilarity -Left 'abc' -Right 'abc' | Should -BeExactly 1.0
        }
    }

    It "共通部分が無ければ 0.0" {
        InModuleScope TextDiff {
            Get-LineSimilarity -Left 'abc' -Right 'xyz' | Should -BeExactly 0.0
        }
    }

    It "桁だけ違う行は高い値になる" {
        InModuleScope TextDiff {
            # この形が「対にしたい」変更の代表例
            $similarity = Get-LineSimilarity -Left '    display_name character varying(100),' -Right '    display_name character varying(20),'

            $similarity | Should -BeGreaterThan 0.5
        }
    }

    It "別の列に差し替わった行は低い値になる" {
        InModuleScope TextDiff {
            # この形は「対にしてはいけない」変更の代表例
            $similarity = Get-LineSimilarity -Left '    status_code character(2) NOT NULL,' -Right '    contact_email_address text,'

            $similarity | Should -BeLessThan 0.5
        }
    }

    It "両方とも空文字なら 1.0（0除算しない）" {
        InModuleScope TextDiff {
            Get-LineSimilarity -Left '' -Right '' | Should -BeExactly 1.0
        }
    }
}

AfterAll {
    Remove-Module -Name TextDiff -ErrorAction SilentlyContinue
}
