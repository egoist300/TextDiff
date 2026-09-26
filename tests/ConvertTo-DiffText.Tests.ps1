# コンソール表示用の変換のテスト。
#
# 守りたいのは 2 点。
#   ・1000 行のスナップショットで数行だけ変わったとき、画面が文脈行で埋まらないこと
#   ・行内の変わった部分が、別の色を当てられる形で分かれていること

BeforeAll {
    # テストのコード自身も StrictMode 3.0 で動かす。モジュールの中は TextDiff.psm1 が設定している
    Set-StrictMode -Version 3.0
    # テスト対象はモジュールとして読み込み、テストの中身はモジュールの中（InModuleScope）で動かす。
    # 非公開の関数はモジュールの中からしか呼べない。ファイルごとに読み直すので、前のファイルが置いた関数は残らない
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\TextDiff\TextDiff.psd1') -Force
    InModuleScope TextDiff {
        function script:Get-Body {
            <#
            .SYNOPSIS
                ConvertTo-DiffText の 1 行の断片を連結した本文を返す。
            .PARAMETER Line
                ConvertTo-DiffText が返した 1 行。
            #>
            param($Line)
            return (($Line.Segments | ForEach-Object -Process { $_.Text }) -join '')
        }
        function script:Get-Marked {
            <#
            .SYNOPSIS
                ConvertTo-DiffText の 1 行を、変わった断片を [] で囲んだ文字列にして返す。
            .PARAMETER Line
                ConvertTo-DiffText が返した 1 行。
            #>
            param($Line)
            return (($Line.Segments | ForEach-Object -Process {
                        if ($_.Changed) { "[$($_.Text)]" } else { $_.Text }
                    }) -join '')
        }
        # 30 行のうち指定した位置だけ桁を変えたデータを作る
        function script:New-TestRow {
            <#
            .SYNOPSIS
                指定した位置の行だけ桁を変えたデータを作り、Get-DiffAlignment の結果を返す。
            .PARAMETER Count
                行数。
            .PARAMETER ChangeAt
                桁を変える行の添字（0 始まり）の一覧。
            #>
            param([int]$Count = 30, [int[]]$ChangeAt = @())
            $before = New-Object -TypeName 'string[]' -ArgumentList $Count
            for ($lineIndex = 0; $lineIndex -lt $Count; $lineIndex++) { $before[$lineIndex] = "    column_{0:D2} character varying(100)," -f $lineIndex }
            $after = $before.Clone()
            foreach ($idx in $ChangeAt) { $after[$idx] = $after[$idx].Replace('varying(100)', 'varying(20)') }
            return @(Get-DiffAlignment -BeforeLines $before -AfterLines $after)
        }
    }
}

Describe "ConvertTo-DiffText" {

    Context "文脈行の絞り込み" {

        It "変更から離れた行を省略表示にまとめる" {
            InModuleScope TextDiff {
                # データは 1000 行を超えることもある。全部の文脈行を出すと
                # 差分の行だけを出すより読みにくくなる
                $lines = @(ConvertTo-DiffText -Rows (New-TestRow -Count 30 -ChangeAt @(3)) -ContextLine 3)

                @($lines | Where-Object -FilterScript { $_.Role -ceq 'Omitted' }).Count | Should -BeExactly 1
                # 変更2行 + 前後の文脈 + 省略1行。30 行がそのまま出ることはない
                $lines.Count | Should -BeLessThan 15
            }
        }

        It "省略した行数を返し、文言は持たない" {
            InModuleScope TextDiff {
                # 「何行飛ばしたか」が分からないと、見えていない部分の量が掴めない。
                # 文言は呼び出し側がカタログから作る（差分エンジンはカタログを使わない）
                $lines = @(ConvertTo-DiffText -Rows (New-TestRow -Count 30 -ChangeAt @(3)) -ContextLine 3)
                $omitted = $lines | Where-Object -FilterScript { $_.Role -ceq 'Omitted' }

                # 変更は 4 行目。前後 3 行を残すと 1〜7 行目が見え、8〜30 行目の 23 行を畳む
                $omitted.OmittedCount | Should -BeExactly 23
                @($omitted.Segments).Count | Should -BeExactly 0
            }
        }

        It "変更が離れて2箇所あれば、その間だけを畳む" {
            InModuleScope TextDiff {
                $lines = @(ConvertTo-DiffText -Rows (New-TestRow -Count 30 -ChangeAt @(3, 20)) -ContextLine 3)

                @($lines | Where-Object -FilterScript { $_.Role -ceq 'Removed' }).Count | Should -BeExactly 2
                @($lines | Where-Object -FilterScript { $_.Role -ceq 'Omitted' }).Count | Should -BeExactly 2
            }
        }

        It "ContextLine が 0 なら文脈行を出さない" {
            InModuleScope TextDiff {
                $lines = @(ConvertTo-DiffText -Rows (New-TestRow -Count 30 -ChangeAt @(3)) -ContextLine 0)

                @($lines | Where-Object -FilterScript { $_.Role -ceq 'Context' }).Count | Should -BeExactly 0
            }
        }

        It "変更が無ければ全体が省略表示になる" {
            InModuleScope TextDiff {
                $lines = @(ConvertTo-DiffText -Rows (New-TestRow -Count 10) -ContextLine 3)

                @($lines | Where-Object -FilterScript { $_.Role -ceq 'Omitted' }).Count | Should -BeExactly 1
            }
        }

        It "空の入力なら空を返す" {
            InModuleScope TextDiff {
                @(ConvertTo-DiffText -Rows @()).Count | Should -BeExactly 0
            }
        }
    }

    Context "行の見せ方" {

        It "書き換えは削除行と追加行の2行になる" {
            InModuleScope TextDiff {
                $rows = @(Get-DiffAlignment -BeforeLines @('    name character varying(100),') -AfterLines @('    name character varying(20),'))
                $lines = @(ConvertTo-DiffText -Rows $rows)

                $lines.Count | Should -BeExactly 2
                $lines[0].Role | Should -BeExactly 'Removed'
                $lines[1].Role | Should -BeExactly 'Added'
            }
        }

        It "書き換えの行内で、変わった部分だけが分かれている" {
            InModuleScope TextDiff {
                # ここが分かれていないと、行全体が同じ色になり強調できない
                $rows = @(Get-DiffAlignment -BeforeLines @('    name character varying(100),') -AfterLines @('    name character varying(20),'))
                $lines = @(ConvertTo-DiffText -Rows $rows)

                Get-Marked -Line $lines[0] | Should -BeExactly '    name character varying([100]),'
                Get-Marked -Line $lines[1] | Should -BeExactly '    name character varying([20]),'
            }
        }

        It "対にならない削除・追加は行内強調を付けない" {
            InModuleScope TextDiff {
                # 別物なので、どこが変わったという話にならない
                $rows = @(Get-DiffAlignment -BeforeLines @('    status_code character(2),') -AfterLines @('    email text,'))
                $lines = @(ConvertTo-DiffText -Rows $rows)

                @($lines[0].Segments | Where-Object -FilterScript { $_.Changed }).Count | Should -BeExactly 0
                @($lines[1].Segments | Where-Object -FilterScript { $_.Changed }).Count | Should -BeExactly 0
            }
        }

        It "見出しに行番号とマーカーが入る" {
            InModuleScope TextDiff {
                $rows = @(Get-DiffAlignment -BeforeLines @('a', 'b') -AfterLines @('a', 'c'))
                $lines = @(ConvertTo-DiffText -Rows $rows)
                $removed = $lines | Where-Object -FilterScript { $_.Role -ceq 'Removed' }
                $added = $lines | Where-Object -FilterScript { $_.Role -ceq 'Added' }

                $removed.Gutter | Should -MatchExactly '2-'
                $added.Gutter | Should -MatchExactly '2\+'
            }
        }

        It "行番号の桁を揃える" {
            InModuleScope TextDiff {
                # 途中で桁が変わると行がガタつき、差分より目に付いてしまう
                $rows = @(New-TestRow -Count 120 -ChangeAt @(5, 100))
                $lines = @(ConvertTo-DiffText -Rows $rows -ContextLine 1)
                $gutters = @($lines | Where-Object -FilterScript { $_.Role -cne 'Omitted' } | ForEach-Object -Process { $_.Gutter.Length })

                # NOTE: @() で囲むこと。Select-Object -Unique の結果が1件だと
                #       スカラーに展開され、StrictMode 下で .Count が落ちる
                @($gutters | Select-Object -Unique).Count | Should -BeExactly 1
            }
        }

        It "本文を連結すると元の行に戻る" {
            InModuleScope TextDiff {
                # ずれると強調が別の場所に付く
                $rows = @(Get-DiffAlignment -BeforeLines @('    name character varying(100),') -AfterLines @('    name character varying(20),'))
                $lines = @(ConvertTo-DiffText -Rows $rows)

                Get-Body -Line $lines[0] | Should -BeExactly '    name character varying(100),'
                Get-Body -Line $lines[1] | Should -BeExactly '    name character varying(20),'
            }
        }
    }

    Context "新規作成・削除" {

        It "before が空なら全て追加行になる" {
            InModuleScope TextDiff {
                $rows = @(Get-DiffAlignment -BeforeLines @() -AfterLines @('a', 'b'))
                $lines = @(ConvertTo-DiffText -Rows $rows)

                @($lines | Where-Object -FilterScript { $_.Role -ceq 'Added' }).Count | Should -BeExactly 2
            }
        }

        It "after が空なら全て削除行になる" {
            InModuleScope TextDiff {
                $rows = @(Get-DiffAlignment -BeforeLines @('a', 'b') -AfterLines @())
                $lines = @(ConvertTo-DiffText -Rows $rows)

                @($lines | Where-Object -FilterScript { $_.Role -ceq 'Removed' }).Count | Should -BeExactly 2
            }
        }
    }

    Context "戻り値の型" {

        It "行は TextDiff.TextLine、断片は TextDiff.Segment の PSCustomObject で返す" {
            InModuleScope TextDiff {
                $lines = @(ConvertTo-DiffText -Rows (New-TestRow -Count 30 -ChangeAt @(3)) -ContextLine 3)

                foreach ($line in $lines) {
                    $line -is [System.Management.Automation.PSCustomObject] | Should -BeTrue
                    $line.PSObject.TypeNames[0] | Should -BeExactly 'TextDiff.TextLine'
                    foreach ($segment in @($line.Segments)) {
                        $segment -is [System.Management.Automation.PSCustomObject] | Should -BeTrue
                        $segment.PSObject.TypeNames[0] | Should -BeExactly 'TextDiff.Segment'
                    }
                }
            }
        }

        It "すべての行が同じ項目を持ち、畳んだ行以外の OmittedCount は 0" {
            InModuleScope TextDiff {
                # 行ごとに項目が違うと、Format-Table の列が最初の行に引きずられ、
                # StrictMode では無い項目を読んだ時点で例外になる
                $lines = @(ConvertTo-DiffText -Rows (New-TestRow -Count 30 -ChangeAt @(3)) -ContextLine 3)

                foreach ($line in $lines) {
                    (@($line.PSObject.Properties | ForEach-Object -Process { $_.Name }) -join ',') | Should -BeExactly 'Gutter,Role,Segments,OmittedCount'
                    if ($line.Role -cne 'Omitted') { $line.OmittedCount | Should -BeExactly 0 }
                }
            }
        }

        It "Get-DiffAlignment の結果ではないものは Rows に受け付けない" {
            InModuleScope TextDiff {
                # 形の違うものを受け取ると、途中で「項目が無い」と分かりにくい失敗をする
                { ConvertTo-DiffText -Rows @(@{ Kind = 'Same'; LeftNo = 1; RightNo = 1; Left = 'a'; Right = 'a' }) } | Should -Throw
            }
        }
    }
}

AfterAll {
    Remove-Module -Name TextDiff -ErrorAction SilentlyContinue
}
