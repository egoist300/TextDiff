# 行内（書き換えられた1行の中）の差分のテスト。
#
# 守りたいのは 2 点。
#   ・強調の位置が意味のある単位に揃うこと（桁なら桁、日付なら日付）
#   ・断片を連結すると必ず元の行に戻ること。ずれると強調が別の場所に付く

BeforeAll {
    # テストのコード自身も StrictMode 3.0 で動かす。モジュールの中は TextDiff.psm1 が設定している
    Set-StrictMode -Version 3.0
    # テスト対象はモジュールとして読み込み、テストの中身はモジュールの中（InModuleScope）で動かす。
    # 非公開の関数はモジュールの中からしか呼べない。ファイルごとに読み直すので、前のファイルが置いた関数は残らない
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\TextDiff\TextDiff.psd1') -Force
    InModuleScope TextDiff {
        # 変更部分を [] で囲んだ文字列にして、期待値を目で読める形にする
        function script:Get-Marked {
            param([array]$Segments)
            return (($Segments | ForEach-Object -Process {
                        if ($_.Changed) { "[$($_.Text)]" } else { $_.Text }
                    }) -join '')
        }

        function script:Get-Joined {
            param([array]$Segments)
            return (($Segments | ForEach-Object -Process { $_.Text }) -join '')
        }
    }
}

Describe "Get-InlineDiff" {

    Context "強調の位置" {

        It "桁の変更は桁の全体を強調する" {
            InModuleScope TextDiff {
                # 文字単位で共通の末尾を先に削ると "0)," が共通と判定され、
                # 中央が "10" と "2" になって「[10]0」「[2]0」という読めない位置に付く。
                # トークン境界で削ることの再発防止
                $diff = Get-InlineDiff -Left '    display_name character varying(100),' -Right '    display_name character varying(20),'

                Get-Marked -Segments $diff.Left | Should -BeExactly '    display_name character varying([100]),'
                Get-Marked -Segments $diff.Right | Should -BeExactly '    display_name character varying([20]),'
            }
        }

        It "日付の変更は変わった部分だけを強調する" {
            InModuleScope TextDiff {
                $diff = Get-InlineDiff -Left 'A001,2026-08-17' -Right 'A001,2026-08-25'

                Get-Marked -Segments $diff.Left | Should -BeExactly 'A001,2026-08-[17]'
                Get-Marked -Segments $diff.Right | Should -BeExactly 'A001,2026-08-[25]'
            }
        }

        It "離れた2箇所の変更をそれぞれ強調する" {
            InModuleScope TextDiff {
                $diff = Get-InlineDiff -Left 'A001,1,CODE,2026-08-17,x' -Right 'A001,2,CODE,2026-08-25,x'

                Get-Marked -Segments $diff.Left | Should -BeExactly 'A001,[1],CODE,2026-08-[17],x'
                Get-Marked -Segments $diff.Right | Should -BeExactly 'A001,[2],CODE,2026-08-[25],x'
            }
        }

        It "追加された部分だけを強調する（削除側には強調が付かない）" {
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

        # 連結して原文に戻らないと、強調が本来と違う位置に付く。
        # 表示の体裁ではなく、証跡としての正しさの問題
        It "どの入力でも連結すると元の行に戻る" {
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

        It "上限を超えたら中央をまとめて変更扱いにする" {
            InModuleScope TextDiff {
                # 行の中がほぼ全面的に違う場合、細かく示しても読めるものにならず、
                # 計算時間だけがかかる
                $left = 'HEAD,' + ((1..60 | ForEach-Object -Process { "a$_" }) -join ',') + ',TAIL'
                $right = 'HEAD,' + ((1..60 | ForEach-Object -Process { "b$_" }) -join ',') + ',TAIL'

                $diff = Get-InlineDiff -Left $left -Right $right -MaxToken 10

                # 中央がひとかたまりになる（前後の共通部分は残る）
                @($diff.Left | Where-Object -FilterScript { $_.Changed }).Count | Should -BeExactly 1
                Get-Joined -Segments $diff.Left | Should -BeExactly $left
            }
        }

        It "上限内なら細かく強調する" {
            InModuleScope TextDiff {
                $left = 'HEAD,a1,KEEP,a2,TAIL'
                $right = 'HEAD,b1,KEEP,b2,TAIL'

                $diff = Get-InlineDiff -Left $left -Right $right -MaxToken 400

                @($diff.Left | Where-Object -FilterScript { $_.Changed }).Count | Should -BeExactly 2
            }
        }
    }

    Context "実際のスナップショットに近い規模" {

        It "長いCSV行を現実的な時間で処理する" {
            InModuleScope TextDiff {
                # 文字単位だと 1 行あたり 100 ミリ秒を超える規模（実測）。
                # 単語単位で比べる理由が失われていないことを守る
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
