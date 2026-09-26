# ConvertTo-HtmlSegment のテスト。

BeforeAll {
    # テストのコード自身も StrictMode 3.0 で動かす。モジュールの中は TextDiff.psm1 が設定している
    Set-StrictMode -Version 3.0
    # テスト対象はモジュールとして読み込み、テストの中身はモジュールの中（InModuleScope）で動かす。
    # 非公開の関数はモジュールの中からしか呼べない。ファイルごとに読み直すので、前のファイルが置いた関数は残らない
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\TextDiff\TextDiff.psd1') -Force
}

Describe "ConvertTo-HtmlSegment" {

    It "変更部分だけを強調タグで包む" {
        InModuleScope TextDiff {
            $segments = @(
                @{ Text = 'varying('; Changed = $false }
                @{ Text = '100'; Changed = $true }
                @{ Text = '),'; Changed = $false }
            )

            ConvertTo-HtmlSegment -Segments $segments | Should -BeExactly 'varying(<b>100</b>),'
        }
    }

    It "エスケープしてから強調タグで包む" {
        InModuleScope TextDiff {
            # 順序が逆だと、強調タグ自体がエスケープされて &lt;b&gt; と表示される
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
