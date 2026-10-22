#Requires -Version 5.1

BeforeAll {
    Set-StrictMode -Version 3.0
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

    It "語の構成文字は ASCII の英数字とアンダースコアだけ" {
        InModuleScope TextDiff {
            # 範囲の境界の前後の記号、全角数字、大文字と小文字の変換で英字に対応する文字（ケルビン記号 U+212A）を確認する。
            $text = 'a/0:9@A[Z`z{１' + [string][char]0x212A + 'b'

            Split-DiffToken -Text $text | Should -BeExactly @('a', '/', '0', ':', '9', '@', 'A', '[', 'Z', '`', 'z', '{', '１', [string][char]0x212A, 'b')
        }
    }

    It "カルチャーに依存する比較で無視される文字も、トークンとして残す" {
        InModuleScope TextDiff {
            # ソフトハイフン（U+00AD）、ゼロ幅非接合子（U+200C）、NUL（U+0000）は、カルチャーに依存する比較では
            # 空文字と等しいと判定される。空文字と比較して除くと、これらの文字が差分の表示から欠落するため。
            $text = 'a' + [string][char]0x00AD + 'b' + [string][char]0x200C + [string][char]0x0000

            $tokens = @(Split-DiffToken -Text $text)

            $tokens.Count | Should -BeExactly 5
            (-join $tokens) | Should -BeExactly $text
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
