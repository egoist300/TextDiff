#Requires -Version 5.1

# Get-InlineDiff のテスト。
#
# 重視するのは次の 2 点。
#   ・強調の位置が意味のある単位に揃うこと（桁数なら桁数、日付なら日付）。
#   ・断片を連結すると必ず元の行と一致すること。一致しないと強調が別の位置に付く。

BeforeAll {
    # テストのコード自身も StrictMode 3.0 で実行する。モジュールの中は TextDiff.psm1 が設定する。
    Set-StrictMode -Version 3.0
    # テスト対象はモジュールとして読み込み、テストはモジュールの中（InModuleScope）で実行する。
    # 非公開の関数はモジュールの中からしか呼び出せない。ファイルごとに読み込み直すため、前のファイルが定義した関数は残らない。
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\TextDiff\TextDiff.psd1') -Force
    InModuleScope TextDiff {
        # 期待値を読みやすくするため、変更箇所を [] で囲んだ文字列で比較する。
        function script:Get-Marked {
            <#
            .SYNOPSIS
                断片の配列を、変更箇所の断片を [] で囲んだ文字列に変換して返す。
            .PARAMETER Segments
                Get-InlineDiff が返した片側の断片。
            #>
            param([array]$Segments)
            return (($Segments | ForEach-Object -Process {
                        if ($_.Changed) { "[$($_.Text)]" } else { $_.Text }
                    }) -join '')
        }

        function script:Get-Joined {
            <#
            .SYNOPSIS
                断片の配列を連結した文字列を返す。
            .PARAMETER Segments
                Get-InlineDiff が返した片側の断片。
            #>
            param([array]$Segments)
            return (($Segments | ForEach-Object -Process { $_.Text }) -join '')
        }
    }
}

Describe "Get-InlineDiff" {

    Context "強調の位置" {

        It "桁数の変更は数値全体を強調する" {
            InModuleScope TextDiff {
                # 文字単位で共通の末尾を先に除去すると "0)," が共通と判定され、
                # 強調が「[10]0」「[2]0」という読めない位置に付く。
                # トークン単位で除去することの再発防止。
                $diff = Get-InlineDiff -Left '    display_name character varying(100),' -Right '    display_name character varying(20),'

                Get-Marked -Segments $diff.Left | Should -BeExactly '    display_name character varying([100]),'
                Get-Marked -Segments $diff.Right | Should -BeExactly '    display_name character varying([20]),'
            }
        }

        It "日付の変更は変更箇所だけを強調する" {
            InModuleScope TextDiff {
                $diff = Get-InlineDiff -Left 'A001,2026-08-17' -Right 'A001,2026-08-25'

                Get-Marked -Segments $diff.Left | Should -BeExactly 'A001,2026-08-[17]'
                Get-Marked -Segments $diff.Right | Should -BeExactly 'A001,2026-08-[25]'
            }
        }

        It "離れた 2 か所の変更をそれぞれ強調する" {
            InModuleScope TextDiff {
                $diff = Get-InlineDiff -Left 'A001,1,CODE,2026-08-17,x' -Right 'A001,2,CODE,2026-08-25,x'

                Get-Marked -Segments $diff.Left | Should -BeExactly 'A001,[1],CODE,2026-08-[17],x'
                Get-Marked -Segments $diff.Right | Should -BeExactly 'A001,[2],CODE,2026-08-[25],x'
            }
        }

        It "追加箇所だけを強調する（削除側は強調しない）" {
            InModuleScope TextDiff {
                $diff = Get-InlineDiff -Left 'A004,サービス,x' -Right 'A004,サービス（第二次）,x'

                Get-Marked -Segments $diff.Left | Should -BeExactly 'A004,サービス,x'
                Get-Marked -Segments $diff.Right | Should -BeExactly 'A004,サービス[（第二次）],x'
            }
        }

        It "同じ行なら強調しない" {
            InModuleScope TextDiff {
                $diff = Get-InlineDiff -Left 'same line' -Right 'same line'

                @($diff.Left | Where-Object -FilterScript { $_.Changed }).Count | Should -BeExactly 0
                @($diff.Right | Where-Object -FilterScript { $_.Changed }).Count | Should -BeExactly 0
            }
        }
    }

    Context "断片の連結" {

        # 連結して元の行と一致しないと、強調が本来と異なる位置に付く。
        # 表示の体裁ではなく、差分の内容の正しさの問題のため。
        It "どの入力でも、連結すると元の行と一致する" {
            InModuleScope TextDiff {
                $pairs = @(
                    @{ L = '    display_name character varying(100),'; R = '    display_name character varying(20),' }
                    @{ L = 'A001,1,CODE,2026-08-17,ops@example.com'; R = 'A001,2,CODE,2026-08-25,ops@example.com' }
                    @{ L = ''; R = 'abc' }
                    @{ L = 'abc'; R = '' }
                    @{ L = 'abc'; R = 'abc' }
                    @{ L = 'xyz'; R = 'abc' }
                    @{ L = '日本語の説明'; R = '日本語の詳しい説明' }
                    @{ L = '   '; R = '  ' }
                )

                foreach ($pair in $pairs) {
                    $d1 = Get-InlineDiff -Left $pair.L -Right $pair.R
                    Get-Joined -Segments $d1.Left | Should -BeExactly $pair.L
                    Get-Joined -Segments $d1.Right | Should -BeExactly $pair.R
                }
            }
        }

        It "片方が空でも失敗しない" {
            InModuleScope TextDiff {
                $diff = Get-InlineDiff -Left '' -Right 'abc'

                Get-Joined -Segments $diff.Left | Should -BeExactly ''
                Get-Marked -Segments $diff.Right | Should -BeExactly '[abc]'
            }
        }

        It "両方空でも失敗しない" {
            InModuleScope TextDiff {
                $diff = Get-InlineDiff -Left '' -Right ''

                @($diff.Left).Count | Should -BeExactly 0
                @($diff.Right).Count | Should -BeExactly 0
            }
        }
    }

    Context "トークン数の上限" {

        It "上限を超えたら、変更箇所全体を 1 つの変更にする" {
            InModuleScope TextDiff {
                # 行の大部分が異なる場合、詳細に示しても読めず、計算時間だけがかかるため。
                $left = 'HEAD,' + ((1..60 | ForEach-Object -Process { "a$_" }) -join ',') + ',TAIL'
                $right = 'HEAD,' + ((1..60 | ForEach-Object -Process { "b$_" }) -join ',') + ',TAIL'

                $diff = Get-InlineDiff -Left $left -Right $right -MaxToken 10

                # 変更箇所が 1 つの断片になる（前後の共通部分は残る）。
                @($diff.Left | Where-Object -FilterScript { $_.Changed }).Count | Should -BeExactly 1
                Get-Joined -Segments $diff.Left | Should -BeExactly $left
            }
        }

        It "行全体では上限を超えても、変更箇所が上限内なら詳細に強調する" {
            InModuleScope TextDiff {
                # 上限は、共通の先頭・末尾を除去した後の変更箇所で判定する。
                # 行全体で判定すると、長い行は 1 か所の変更で行全体が変更扱いになるため。
                $left = ((1..60 | ForEach-Object -Process { "k$_" }) -join ',') + ',old,' + ((1..60 | ForEach-Object -Process { "t$_" }) -join ',')
                $right = ((1..60 | ForEach-Object -Process { "k$_" }) -join ',') + ',new,' + ((1..60 | ForEach-Object -Process { "t$_" }) -join ',')

                $diff = Get-InlineDiff -Left $left -Right $right -MaxToken 10

                @(Split-DiffToken -Text $left).Count | Should -BeGreaterThan 10
                @($diff.Left | Where-Object -FilterScript { $_.Changed } | ForEach-Object -Process { $_.Text }) | Should -BeExactly @('old')
            }
        }

        It "上限内なら詳細に強調する" {
            InModuleScope TextDiff {
                $left = 'HEAD,a1,KEEP,a2,TAIL'
                $right = 'HEAD,b1,KEEP,b2,TAIL'

                $diff = Get-InlineDiff -Left $left -Right $right -MaxToken 400

                @($diff.Left | Where-Object -FilterScript { $_.Changed }).Count | Should -BeExactly 2
            }
        }
    }

    Context "実際のデータに近い規模" {

        It "長い CSV の行を実用的な時間で処理する" {
            InModuleScope TextDiff {
                # 文字単位では 1 行あたり 100 ミリ秒を超える規模（実測）。
                # トークン単位で比較する理由である処理速度が保たれていることを確認する。
                $left = "12345,PARTNER000123,2026-08-20 01:02:03," + ('あいうえお' * 90)
                $right = "12345,PARTNER000123,2026-09-30 01:02:03," + ('あいうえお' * 90)

                $sw = [System.Diagnostics.Stopwatch]::StartNew()
                $diff = Get-InlineDiff -Left $left -Right $right
                $sw.Stop()

                Get-Joined -Segments $diff.Left | Should -BeExactly $left
                $sw.Elapsed.TotalMilliseconds | Should -BeLessThan 200
            }
        }
    }
}

AfterAll {
    Remove-Module -Name TextDiff -ErrorAction SilentlyContinue
}
