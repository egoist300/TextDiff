#Requires -Version 5.1

# ConvertTo-HtmlSegment のテスト。

BeforeAll {
    # テストのコード自身も StrictMode 3.0 で実行する。モジュールの中は TextDiff.psm1 が設定する。
    Set-StrictMode -Version 3.0
    # テスト対象はモジュールとして読み込み、テストはモジュールの中（InModuleScope）で実行する。
    # 非公開の関数はモジュールの中からしか呼び出せない。ファイルごとに読み込み直すため、前のファイルが定義した関数は残らない。
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\TextDiff\TextDiff.psd1') -Force
}

Describe "ConvertTo-HtmlSegment" {

    It "変更箇所だけを強調のタグで囲む" {
        InModuleScope TextDiff {
            $segments = @(
                @{ Text = 'varying('; Changed = $false }
                @{ Text = '100'; Changed = $true }
                @{ Text = '),'; Changed = $false }
            )

            ConvertTo-HtmlSegment -Segments $segments | Should -BeExactly 'varying(<b>100</b>),'
        }
    }

    It "エスケープしてから強調のタグで囲む" {
        InModuleScope TextDiff {
            # 順序が逆だと、強調のタグ自体がエスケープされて &lt;b&gt; と表示されるため。
            $segments = @(@{ Text = '<script>'; Changed = $true })

            ConvertTo-HtmlSegment -Segments $segments | Should -BeExactly '<b>&lt;script&gt;</b>'
        }
    }

    It "null なら空文字を返す" {
        InModuleScope TextDiff {
            ConvertTo-HtmlSegment -Segments $null | Should -BeExactly ''
        }
    }
}

AfterAll {
    Remove-Module -Name TextDiff -ErrorAction SilentlyContinue
}
