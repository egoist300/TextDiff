#Requires -Version 5.1

# Format-DiffGutter のテスト。

BeforeAll {
    # テストのコード自身も StrictMode 3.0 で実行する。モジュールの中は TextDiff.psm1 が設定する。
    Set-StrictMode -Version 3.0
    # テスト対象はモジュールとして読み込み、テストはモジュールの中（InModuleScope）で実行する。
    # 非公開の関数はモジュールの中からしか呼び出せない。ファイルごとに読み込み直すため、前のファイルが定義した関数は残らない。
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\TextDiff\TextDiff.psd1') -Force
}

Describe "Format-DiffGutter" {

    It "行番号を指定した桁数で右寄せし、マーカーを付ける" {
        InModuleScope TextDiff {
            Format-DiffGutter -Number 6 -Marker '-' -Width 3 | Should -BeExactly '    6- '
        }
    }

    It "行番号が無いときは、桁数分の空白を配置する" {
        InModuleScope TextDiff {
            # 反対側にしか無い行でも、見出しの幅を統一するため。
            Format-DiffGutter -Marker '+' -Width 3 | Should -BeExactly '     + '
        }
    }

    It "桁数を超える行番号は切り詰めない" {
        InModuleScope TextDiff {
            Format-DiffGutter -Number 12345 -Marker ' ' -Width 3 | Should -BeExactly '  12345  '
        }
    }
}

AfterAll {
    Remove-Module -Name TextDiff -ErrorAction SilentlyContinue
}
