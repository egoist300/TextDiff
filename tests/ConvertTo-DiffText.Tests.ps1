#Requires -Version 5.1

# ConvertTo-DiffText のテスト。
#
# 重視するのは次の 2 点。
#   ・1000 行のうち数行だけ変更されたとき、画面が文脈行で埋まらないこと。
#   ・行内の変更箇所が、別の色で表示できる断片に分割されていること。

BeforeAll {
    # テストのコード自身も StrictMode 3.0 で実行する。モジュールの中は TextDiff.psm1 が設定する。
    Set-StrictMode -Version 3.0
    # テスト対象はモジュールとして読み込み、テストはモジュールの中（InModuleScope）で実行する。
    # 非公開の関数はモジュールの中からしか呼び出せない。ファイルごとに読み込み直すため、前のファイルが定義した関数は残らない。
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
                ConvertTo-DiffText の 1 行を、変更箇所の断片を [] で囲んだ文字列に変換して返す。
            .PARAMETER Line
                ConvertTo-DiffText が返した 1 行。
            #>
            param($Line)
            return (($Line.Segments | ForEach-Object -Process {
                        if ($_.Changed) { "[$($_.Text)]" } else { $_.Text }
                    }) -join '')
        }
        function script:New-TestRow {
            <#
            .SYNOPSIS
                指定した位置の行だけ桁数を変更したデータを作成し、Get-DiffAlignment の結果を返す。
            .PARAMETER Count
                行数。
            .PARAMETER ChangeAt
                桁数を変更する行の添字（0 始まり）の配列。
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

    Context "文脈行の省略" {

        It "変更行から離れた行を省略行にまとめる" {
            InModuleScope TextDiff {
                # データは 1000 行を超えることもある。すべての文脈行を表示すると、差分が読みにくくなるため。
                $lines = @(ConvertTo-DiffText -Rows (New-TestRow -Count 30 -ChangeAt @(3)) -ContextLine 3)

                @($lines | Where-Object -FilterScript { $_.Role -ceq 'Omitted' }).Count | Should -BeExactly 1
                # 変更 2 行、前後の文脈行、省略行 1 行。30 行すべてを表示することはない。
                $lines.Count | Should -BeLessThan 15
            }
        }

        It "省略した行数を返し、文言は持たない" {
            InModuleScope TextDiff {
                # 省略した行数が分からないと、表示されていない部分の量を把握できないため。
                # 省略行の文言は呼び出し側が作成する。
                $lines = @(ConvertTo-DiffText -Rows (New-TestRow -Count 30 -ChangeAt @(3)) -ContextLine 3)
                $omitted = $lines | Where-Object -FilterScript { $_.Role -ceq 'Omitted' }

                # 変更は 4 行目。前後 3 行を残すと 1〜7 行目を表示し、8〜30 行目の 23 行を省略する。
                $omitted.OmittedCount | Should -BeExactly 23
                @($omitted.Segments).Count | Should -BeExactly 0
            }
        }

        It "変更が 2 か所に離れていれば、その間だけを省略する" {
            InModuleScope TextDiff {
                $lines = @(ConvertTo-DiffText -Rows (New-TestRow -Count 30 -ChangeAt @(3, 20)) -ContextLine 3)

                @($lines | Where-Object -FilterScript { $_.Role -ceq 'Removed' }).Count | Should -BeExactly 2
                @($lines | Where-Object -FilterScript { $_.Role -ceq 'Omitted' }).Count | Should -BeExactly 2
            }
        }

        It "ContextLine が 0 なら文脈行を表示しない" {
            InModuleScope TextDiff {
                $lines = @(ConvertTo-DiffText -Rows (New-TestRow -Count 30 -ChangeAt @(3)) -ContextLine 0)

                @($lines | Where-Object -FilterScript { $_.Role -ceq 'Context' }).Count | Should -BeExactly 0
            }
        }

        It "変更が無ければ全体が省略行になる" {
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

    Context "行の表示形式" {

        It "変更行は削除行と追加行の 2 行になる" {
            InModuleScope TextDiff {
                $rows = @(Get-DiffAlignment -BeforeLines @('    name character varying(100),') -AfterLines @('    name character varying(20),'))
                $lines = @(ConvertTo-DiffText -Rows $rows)

                $lines.Count | Should -BeExactly 2
                $lines[0].Role | Should -BeExactly 'Removed'
                $lines[1].Role | Should -BeExactly 'Added'
            }
        }

        It "変更行の行内で、変更箇所だけが別の断片に分割される" {
            InModuleScope TextDiff {
                # 断片に分割されていないと、行全体が同じ色になり、変更箇所を強調できないため。
                $rows = @(Get-DiffAlignment -BeforeLines @('    name character varying(100),') -AfterLines @('    name character varying(20),'))
                $lines = @(ConvertTo-DiffText -Rows $rows)

                Get-Marked -Line $lines[0] | Should -BeExactly '    name character varying([100]),'
                Get-Marked -Line $lines[1] | Should -BeExactly '    name character varying([20]),'
            }
        }

        It "対応付けていない削除行と追加行は強調しない" {
            InModuleScope TextDiff {
                # 別の行のため、行内の変更箇所は無い。
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

        It "行番号の桁数を揃える" {
            InModuleScope TextDiff {
                # 途中で桁数が変わると行の位置がずれ、差分より目立つため。
                $rows = @(New-TestRow -Count 120 -ChangeAt @(5, 100))
                $lines = @(ConvertTo-DiffText -Rows $rows -ContextLine 1)
                $gutters = @($lines | Where-Object -FilterScript { $_.Role -cne 'Omitted' } | ForEach-Object -Process { $_.Gutter.Length })

                # NOTE: @() で囲むこと。Select-Object -Unique の結果が 1 件だとスカラーに展開され、
                #       StrictMode では .Count が例外になる。
                @($gutters | Select-Object -Unique).Count | Should -BeExactly 1
            }
        }

        It "本文を連結すると元の行と一致する" {
            InModuleScope TextDiff {
                # 連結結果が元の行と一致しないと、強調が別の位置に付くため。
                $rows = @(Get-DiffAlignment -BeforeLines @('    name character varying(100),') -AfterLines @('    name character varying(20),'))
                $lines = @(ConvertTo-DiffText -Rows $rows)

                Get-Body -Line $lines[0] | Should -BeExactly '    name character varying(100),'
                Get-Body -Line $lines[1] | Should -BeExactly '    name character varying(20),'
            }
        }
    }

    Context "新規作成・削除" {

        It "変更前が空なら、すべて追加行になる" {
            InModuleScope TextDiff {
                $rows = @(Get-DiffAlignment -BeforeLines @() -AfterLines @('a', 'b'))
                $lines = @(ConvertTo-DiffText -Rows $rows)

                @($lines | Where-Object -FilterScript { $_.Role -ceq 'Added' }).Count | Should -BeExactly 2
            }
        }

        It "変更後が空なら、すべて削除行になる" {
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

        It "すべての行が同じ項目を持ち、省略行以外の OmittedCount は 0" {
            InModuleScope TextDiff {
                # 行ごとに項目が異なると、Format-Table の列が最初の行で決まり、
                # StrictMode では存在しない項目の参照が例外になるため。
                $lines = @(ConvertTo-DiffText -Rows (New-TestRow -Count 30 -ChangeAt @(3)) -ContextLine 3)

                foreach ($line in $lines) {
                    (@($line.PSObject.Properties | ForEach-Object -Process { $_.Name }) -join ',') | Should -BeExactly 'Gutter,Role,Segments,OmittedCount'
                    if ($line.Role -cne 'Omitted') { $line.OmittedCount | Should -BeExactly 0 }
                }
            }
        }

        It "Get-DiffAlignment の結果ではないものは Rows に受け付けない" {
            InModuleScope TextDiff {
                # 形式の異なる入力を受け取ると、処理の途中で「項目が無い」という分かりにくいエラーになるため。
                { ConvertTo-DiffText -Rows @(@{ Kind = 'Same'; LeftNo = 1; RightNo = 1; Left = 'a'; Right = 'a' }) } | Should -Throw
            }
        }
    }
}

AfterAll {
    Remove-Module -Name TextDiff -ErrorAction SilentlyContinue
}
