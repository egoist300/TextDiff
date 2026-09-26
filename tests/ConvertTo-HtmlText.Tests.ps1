# ConvertTo-HtmlText のテスト。

BeforeAll {
    # テストのコード自身も StrictMode 3.0 で動かす。モジュールの中は TextDiff.psm1 が設定している
    Set-StrictMode -Version 3.0
    # テスト対象はモジュールとして読み込み、テストの中身はモジュールの中（InModuleScope）で動かす。
    # 非公開の関数はモジュールの中からしか呼べない。ファイルごとに読み直すので、前のファイルが置いた関数は残らない
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\TextDiff\TextDiff.psd1') -Force
}

Describe "ConvertTo-HtmlText" {

    It "HTML の特殊文字をエスケープする" {
        InModuleScope TextDiff {
            ConvertTo-HtmlText -Text '<b>&"' | Should -BeExactly '&lt;b&gt;&amp;&quot;'
        }
    }

    It "アンパサンドを二重にエスケープしない" {
        InModuleScope TextDiff {
            # & を最後に置換すると、他の置換で作った & まで壊れる
            ConvertTo-HtmlText -Text '<' | Should -BeExactly '&lt;'
        }
    }

    It "空文字でも失敗しない" {
        InModuleScope TextDiff {
            ConvertTo-HtmlText -Text '' | Should -BeExactly ''
        }
    }
}

AfterAll {
    Remove-Module -Name TextDiff -ErrorAction SilentlyContinue
}
