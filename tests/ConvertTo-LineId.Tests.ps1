#Requires -Version 5.1

# ConvertTo-LineId のテスト。

BeforeAll {
    # テストのコード自身も StrictMode 3.0 で実行する。モジュールの中は TextDiff.psm1 が設定する。
    Set-StrictMode -Version 3.0
    # テスト対象はモジュールとして読み込み、テストはモジュールの中（InModuleScope）で実行する。
    # 非公開の関数はモジュールの中からしか呼び出せない。ファイルごとに読み込み直すため、前のファイルが定義した関数は残らない。
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\TextDiff\TextDiff.psd1') -Force
}

Describe "ConvertTo-LineId" {

    It "同じ内容の行には同じ ID を割り当てる" {
        InModuleScope TextDiff {
            $ids = ConvertTo-LineId -Left @('a', 'b', 'a') -Right @('b', 'a')

            $ids.Left[0] | Should -BeExactly $ids.Left[2]
            $ids.Left[0] | Should -BeExactly $ids.Right[1]
            $ids.Left[1] | Should -BeExactly $ids.Right[0]
        }
    }

    It "大文字と小文字を区別する" {
        InModuleScope TextDiff {
            # データでは大文字と小文字の違いも変更に当たる。同一視すると変更を見落とすため。
            $ids = ConvertTo-LineId -Left @('Alice') -Right @('alice')

            $ids.Left[0] | Should -Not -BeExactly $ids.Right[0]
        }
    }

    It "空の配列でも失敗しない" {
        InModuleScope TextDiff {
            $ids = ConvertTo-LineId -Left @() -Right @()

            $ids.Left.Length | Should -BeExactly 0
            $ids.Right.Length | Should -BeExactly 0
        }
    }
}

AfterAll {
    Remove-Module -Name TextDiff -ErrorAction SilentlyContinue
}
