#Requires -Version 5.1

# ConvertTo-HtmlText のテスト。

BeforeAll {
    # テストのコード自身も StrictMode 3.0 で実行する。モジュールの中は TextDiff.psm1 が設定する。
    Set-StrictMode -Version 3.0
    # テスト対象はモジュールとして読み込み、テストはモジュールの中（InModuleScope）で実行する。
    # 非公開の関数はモジュールの中からしか呼び出せない。ファイルごとに読み込み直すため、前のファイルが定義した関数は残らない。
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
            # & を最後に置換すると、他の置換で生成した & まで二重にエスケープされるため。
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
