# ConvertTo-LineId のテスト。

BeforeAll {
    # テストのコード自身も StrictMode 3.0 で動かす。モジュールの中は TextDiff.psm1 が設定している
    Set-StrictMode -Version 3.0
    # テスト対象はモジュールとして読み込み、テストの中身はモジュールの中（InModuleScope）で動かす。
    # 非公開の関数はモジュールの中からしか呼べない。ファイルごとに読み直すので、前のファイルが置いた関数は残らない
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\TextDiff\TextDiff.psd1') -Force
}

Describe "ConvertTo-LineId" {

    It "同じ内容の行には同じIDを割り当てる" {
        InModuleScope TextDiff {
            $ids = ConvertTo-LineId -Left @('a', 'b', 'a') -Right @('b', 'a')

            $ids.Left[0] | Should -BeExactly $ids.Left[2]
            $ids.Left[0] | Should -BeExactly $ids.Right[1]
            $ids.Left[1] | Should -BeExactly $ids.Right[0]
        }
    }

    It "大文字と小文字を区別する" {
        InModuleScope TextDiff {
            # PostgreSQL のデータやクォート識別子では大小文字が意味を持つ。
            # 同一視すると「変わっていないのに変わった」「変わったのに気づかない」の両方が起きる
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
