#Requires -Version 5.1

# Get-DiffAlignment のテスト。
#
# 行の対応付けを行うのはこの関数だけで、コンソール表示も HTML 出力もこの結果を使うため、テストを重点的に置く。
#
# 特に重視するのは Changed の判定。隣接する削除行と追加行をすべて対応付けると、
# 無関係な削除と追加まで変更と誤認し、行内の強調が行全体に付いて読めなくなる。

BeforeAll {
    # テストのコード自身も StrictMode 3.0 で実行する。モジュールの中は TextDiff.psm1 が設定する。
    Set-StrictMode -Version 3.0
    # テスト対象はモジュールとして読み込み、テストはモジュールの中（InModuleScope）で実行する。
    # 非公開の関数はモジュールの中からしか呼び出せない。ファイルごとに読み込み直すため、前のファイルが定義した関数は残らない。
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\TextDiff\TextDiff.psd1') -Force
    InModuleScope TextDiff {
        # 期待値と比較しやすくするため、文字列に変換する。
        function script:Get-Shape {
            <#
            .SYNOPSIS
                対応付けの結果を「種類:左の行番号>右の行番号」の文字列の配列に変換する。
            .PARAMETER Rows
                Get-DiffAlignment が返した行の対応付け。
            #>
            param([array]$Rows)
            return ($Rows | ForEach-Object -Process {
                    "{0}:{1}>{2}" -f $_.Kind,
                    $(if ($null -ne $_.LeftNo) { $_.LeftNo } else { '-' }),
                    $(if ($null -ne $_.RightNo) { $_.RightNo } else { '-' })
                }) -join ' '
        }
    }
}

Describe "Get-DiffAlignment" {

    Context "基本の対応付け" {

        It "すべて同じなら、すべて Same になる" {
            InModuleScope TextDiff {
                $rows = @(Get-DiffAlignment -BeforeLines @('a', 'b') -AfterLines @('a', 'b'))

                Get-Shape -Rows $rows | Should -BeExactly 'Same:1>1 Same:2>2'
            }
        }

        It "行番号は 1 始まりで、左右それぞれ独立に増える" {
            InModuleScope TextDiff {
                # 差分の位置を示せることが、Compare-Object に対する利点のため。
                $rows = @(Get-DiffAlignment -BeforeLines @('a', 'b', 'c') -AfterLines @('a', 'c'))

                Get-Shape -Rows $rows | Should -BeExactly 'Same:1>1 Deleted:2>- Same:3>2'
            }
        }

        It "追加だけの場合" {
            InModuleScope TextDiff {
                $rows = @(Get-DiffAlignment -BeforeLines @('a') -AfterLines @('a', 'b'))

                Get-Shape -Rows $rows | Should -BeExactly 'Same:1>1 Added:->2'
            }
        }

        It "変更前が空なら、すべて Added" {
            InModuleScope TextDiff {
                # 新規作成の場合。変更前が空になるのは正常な状態。
                $rows = @(Get-DiffAlignment -BeforeLines @() -AfterLines @('a', 'b'))

                Get-Shape -Rows $rows | Should -BeExactly 'Added:->1 Added:->2'
            }
        }

        It "変更後が空なら、すべて Deleted" {
            InModuleScope TextDiff {
                # 削除の場合。
                $rows = @(Get-DiffAlignment -BeforeLines @('a', 'b') -AfterLines @())

                Get-Shape -Rows $rows | Should -BeExactly 'Deleted:1>- Deleted:2>-'
            }
        }

        It "空行を含む行の配列を処理できる" {
            InModuleScope TextDiff {
                # 比較する行には空行が含まれる。Mandatory な [string[]] は AllowEmptyString が無いと、
                # 空文字を含む配列を「引数が空の文字列である」として拒否する。
                # （実際の実行で発覚した。単体テストが空行を渡していなかった）
                $before = @('CREATE TABLE t (', '', '    id integer', '', ');')
                $after = @('CREATE TABLE t (', '', '    id bigint', '', ');')

                $rows = @(Get-DiffAlignment -BeforeLines $before -AfterLines $after)

                Get-Shape -Rows $rows | Should -BeExactly 'Same:1>1 Same:2>2 Changed:3>3 Same:4>4 Same:5>5'
            }
        }

        It "空行だけの配列でも失敗しない" {
            InModuleScope TextDiff {
                { Get-DiffAlignment -BeforeLines @('') -AfterLines @('') } | Should -Not -Throw
            }
        }

        It "両方空なら結果も空" {
            InModuleScope TextDiff {
                $rows = @(Get-DiffAlignment -BeforeLines @() -AfterLines @())

                $rows.Count | Should -BeExactly 0
            }
        }

        It "共通行を除外しない（文脈行が残る）" {
            InModuleScope TextDiff {
                # Compare-Object を使わない理由。Compare-Object は一致する行を返さないため、文脈を表示できない。
                # 変更の前後に文脈を表示できることが、差分を読みやすくする前提のため。
                $rows = @(Get-DiffAlignment -BeforeLines @('a', 'b', 'c') -AfterLines @('a', 'x', 'c'))

                @($rows | Where-Object -FilterScript { $_.Kind -ceq 'Same' }).Count | Should -BeExactly 2
            }
        }
    }

    Context "Changed（変更）の判定" {

        It "桁数だけ異なる行は Changed として対応付ける" {
            InModuleScope TextDiff {
                $rows = @(Get-DiffAlignment -BeforeLines @('    display_name character varying(100),') -AfterLines @('    display_name character varying(20),'))

                Get-Shape -Rows $rows | Should -BeExactly 'Changed:1>1'
                $rows[0].Left | Should -MatchExactly '100'
                $rows[0].Right | Should -MatchExactly '20'
            }
        }

        It "別の列への置き換えは Changed にしない" {
            InModuleScope TextDiff {
                # 削除と追加が偶然隣接しただけ。対応付けると行全体が強調されて読めなくなるため。
                $rows = @(Get-DiffAlignment -BeforeLines @('    status_code character(2) NOT NULL,') -AfterLines @('    contact_email_address text,'))

                Get-Shape -Rows $rows | Should -BeExactly 'Deleted:1>- Added:->1'
            }
        }

        It "変更と、無関係な削除・追加が混在しても誤認しない" {
            InModuleScope TextDiff {
                # 1 つのテーブルで、桁数の変更・列の削除・列の追加が同時に起きた場合。
                $before = @(
                    'CREATE TABLE app.partner ('
                    '    display_name character varying(100),'
                    '    company_code character varying(10),'
                    '    status_code character(2) NOT NULL,'
                    ');'
                )
                $after = @(
                    'CREATE TABLE app.partner ('
                    '    display_name character varying(20),'
                    '    company_code character varying(10),'
                    '    contact_email_address text,'
                    ');'
                )

                $rows = @(Get-DiffAlignment -BeforeLines $before -AfterLines $after)

                Get-Shape -Rows $rows | Should -BeExactly 'Same:1>1 Changed:2>2 Same:3>3 Deleted:4>- Added:->4 Same:5>5'
            }
        }

        It "しきい値を上げると対応付けなくなる" {
            InModuleScope TextDiff {
                # 判定がしきい値に従っていることを確認する。
                # NOTE: $args は自動変数のため、スプラッティング用の変数名に使うと lint が指摘する。
                $lines = @{
                    BeforeLines = @('    display_name character varying(100),')
                    AfterLines  = @('    display_name character varying(20),')
                }
                $loose = @(Get-DiffAlignment @lines -SimilarityThreshold 0.5)
                $strict = @(Get-DiffAlignment @lines -SimilarityThreshold 0.99)

                Get-Shape -Rows $loose | Should -BeExactly 'Changed:1>1'
                Get-Shape -Rows $strict | Should -BeExactly 'Deleted:1>- Added:->1'
            }
        }

        It "削除行の方が多い場合、残りは Deleted のまま残す" {
            InModuleScope TextDiff {
                $before = @('aaa1', 'aaa2', 'aaa3')
                $after = @('aaa9')

                $rows = @(Get-DiffAlignment -BeforeLines $before -AfterLines $after)

                @($rows | Where-Object -FilterScript { $_.Kind -ceq 'Changed' }).Count | Should -BeExactly 1
                @($rows | Where-Object -FilterScript { $_.Kind -ceq 'Deleted' }).Count | Should -BeExactly 2
            }
        }

        It "追加行の方が多い場合、残りは Added のまま残す" {
            InModuleScope TextDiff {
                $before = @('aaa1')
                $after = @('aaa7', 'aaa8', 'aaa9')

                $rows = @(Get-DiffAlignment -BeforeLines $before -AfterLines $after)

                @($rows | Where-Object -FilterScript { $_.Kind -ceq 'Changed' }).Count | Should -BeExactly 1
                @($rows | Where-Object -FilterScript { $_.Kind -ceq 'Added' }).Count | Should -BeExactly 2
            }
        }
    }

    Context "戻り値の形" {

        It "Changed には左右の内容が両方入る" {
            InModuleScope TextDiff {
                $rows = @(Get-DiffAlignment -BeforeLines @('aaa1') -AfterLines @('aaa2'))

                $rows[0].Left | Should -BeExactly 'aaa1'
                $rows[0].Right | Should -BeExactly 'aaa2'
            }
        }

        It "Deleted の右側と Added の左側は null" {
            InModuleScope TextDiff {
                # 表示側が、反対側に対応する行が無いことを斜線で示すために使う。
                $rows = @(Get-DiffAlignment -BeforeLines @('a') -AfterLines @('b'))

                ($rows | Where-Object -FilterScript { $_.Kind -ceq 'Deleted' }).Right | Should -BeNullOrEmpty
                ($rows | Where-Object -FilterScript { $_.Kind -ceq 'Deleted' }).RightNo | Should -BeNullOrEmpty
                ($rows | Where-Object -FilterScript { $_.Kind -ceq 'Added' }).Left | Should -BeNullOrEmpty
                ($rows | Where-Object -FilterScript { $_.Kind -ceq 'Added' }).LeftNo | Should -BeNullOrEmpty
            }
        }

        It "内部で使う Order を戻り値に残さない" {
            InModuleScope TextDiff {
                # 並べ替え用の一時的な項目。呼び出し側に見えると、表示側がこの項目に依存するため。
                $rows = @(Get-DiffAlignment -BeforeLines @('a', 'b') -AfterLines @('x', 'y'))

                foreach ($row in $rows) {
                    @($row.PSObject.Properties | ForEach-Object -Process { $_.Name }) -ccontains 'Order' | Should -BeFalse
                }
            }
        }

        It "行は型名 TextDiff.DiffRow の PSCustomObject で、項目は Kind, LeftNo, RightNo, Left, Right の順" {
            InModuleScope TextDiff {
                # ハッシュテーブルで返すと、表示したときに Name と Value の縦の一覧になり、
                # Format-Table や Select-Object で列として扱えないため。
                $rows = @(Get-DiffAlignment -BeforeLines @('a', 'b', 'c') -AfterLines @('a', 'x', 'c', 'd'))

                $rows.Count | Should -BeGreaterThan 0
                foreach ($row in $rows) {
                    $row -is [System.Management.Automation.PSCustomObject] | Should -BeTrue
                    $row.PSObject.TypeNames[0] | Should -BeExactly 'TextDiff.DiffRow'
                    (@($row.PSObject.Properties | ForEach-Object -Process { $_.Name }) -join ',') | Should -BeExactly 'Kind,LeftNo,RightNo,Left,Right'
                }
            }
        }
    }

    Context "実際のデータに近い規模" {

        It "1000 行のうち数行だけ変更された場合を、実用的な時間で処理する" {
            InModuleScope TextDiff {
                # 動的計画法では約 2.8 秒かかる規模（実測）。
                # Myers 法を使う理由である処理速度が保たれていることを確認する。
                $before = New-Object -TypeName 'string[]' -ArgumentList 1000
                for ($lineIndex = 0; $lineIndex -lt 1000; $lineIndex++) {
                    $before[$lineIndex] = "{0},PARTNER{0:D6},2026-08-20 01:02:03,{1}" -f $lineIndex, ('x' * 200)
                }
                $after = $before.Clone()
                foreach ($idx in @(100, 300, 500, 700, 900)) {
                    $after[$idx] = $after[$idx].Replace('2026-08-20', '2026-09-30')
                }

                $sw = [System.Diagnostics.Stopwatch]::StartNew()
                $rows = @(Get-DiffAlignment -BeforeLines $before -AfterLines $after)
                $sw.Stop()

                @($rows | Where-Object -FilterScript { $_.Kind -ceq 'Changed' }).Count | Should -BeExactly 5
                @($rows | Where-Object -FilterScript { $_.Kind -ceq 'Same' }).Count | Should -BeExactly 995
                $sw.Elapsed.TotalSeconds | Should -BeLessThan 1.0
            }
        }
    }
}

AfterAll {
    Remove-Module -Name TextDiff -ErrorAction SilentlyContinue
}
