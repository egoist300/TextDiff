# before/after の行の対応づけのテスト。
#
# ここが差分表示の「知識」を持つ唯一の場所で、コンソール表示も HTML 出力も
# この結果を読むだけなので、テストはここに厚く置く。
#
# 特に重視するのは Changed の判定。素朴に「隣り合った削除と追加を対にする」と
# 実装すると、無関係な削除と追加まで書き換えと誤認し、行内強調が行全体に付いて
# かえって読めなくなる。

BeforeAll {
    # テストのコード自身も StrictMode 3.0 で動かす。モジュールの中は TextDiff.psm1 が設定している
    Set-StrictMode -Version 3.0
    # テスト対象はモジュールとして読み込み、テストの中身はモジュールの中（InModuleScope）で動かす。
    # 非公開の関数はモジュールの中からしか呼べない。ファイルごとに読み直すので、前のファイルが置いた関数は残らない
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\TextDiff\TextDiff.psd1') -Force
    InModuleScope TextDiff {
        # 対応づけの結果を "種類:左行番号>右行番号" の並びに畳んで比較しやすくする
        function script:Get-Shape {
            <#
            .SYNOPSIS
                対応づけの結果を「種類:左の行番号>右の行番号」の並びにして、期待値と比べやすくする。
            .PARAMETER Rows
                Get-DiffAlignment が返した行の対応づけ。
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

    Context "基本の対応づけ" {

        It "全て同じなら全て Same になる" {
            InModuleScope TextDiff {
                $rows = @(Get-DiffAlignment -BeforeLines @('a', 'b') -AfterLines @('a', 'b'))

                Get-Shape -Rows $rows | Should -BeExactly 'Same:1>1 Same:2>2'
            }
        }

        It "行番号は 1 始まりで、左右それぞれ独立に進む" {
            InModuleScope TextDiff {
                # 「どこの差分か」を位置で示せることが、Compare-Object に対する利点そのもの
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

        It "before が空なら全て Added" {
            InModuleScope TextDiff {
                # 新規作成時。before スナップショットが空になるのは正常な状態
                $rows = @(Get-DiffAlignment -BeforeLines @() -AfterLines @('a', 'b'))

                Get-Shape -Rows $rows | Should -BeExactly 'Added:->1 Added:->2'
            }
        }

        It "after が空なら全て Deleted" {
            InModuleScope TextDiff {
                # 削除時
                $rows = @(Get-DiffAlignment -BeforeLines @('a', 'b') -AfterLines @())

                Get-Shape -Rows $rows | Should -BeExactly 'Deleted:1>- Deleted:2>-'
            }
        }

        It "空行を含むスナップショットを扱える" {
            InModuleScope TextDiff {
                # pg_dump の出力には空行が含まれる。Mandatory な [string[]] は
                # AllowEmptyString が無いと、空文字を含む配列を
                # 「引数が空の文字列である」として拒否し、テーブル定義の差分で必ず落ちる
                # （local 環境の実走で発覚。単体テストが空行を渡していなかった）
                $before = @('CREATE TABLE t (', '', '    id integer', '', ');')
                $after = @('CREATE TABLE t (', '', '    id bigint', '', ');')

                $rows = @(Get-DiffAlignment -BeforeLines $before -AfterLines $after)

                Get-Shape -Rows $rows | Should -BeExactly 'Same:1>1 Same:2>2 Changed:3>3 Same:4>4 Same:5>5'
            }
        }

        It "空行だけのスナップショットでも失敗しない" {
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

        It "変わっていない行を捨てない（文脈行が残る）" {
            InModuleScope TextDiff {
                # Compare-Object を使わない理由。一致行を捨てるため、文脈を出せない。
                # 変更の前後に文脈を出せることが、差分を読みやすくする前提
                $rows = @(Get-DiffAlignment -BeforeLines @('a', 'b', 'c') -AfterLines @('a', 'x', 'c'))

                @($rows | Where-Object -FilterScript { $_.Kind -ceq 'Same' }).Count | Should -BeExactly 2
            }
        }
    }

    Context "Changed（書き換え）の判定" {

        It "桁だけ違う行は Changed として対にする" {
            InModuleScope TextDiff {
                $rows = @(Get-DiffAlignment -BeforeLines @('    display_name character varying(100),') -AfterLines @('    display_name character varying(20),'))

                Get-Shape -Rows $rows | Should -BeExactly 'Changed:1>1'
                $rows[0].Left | Should -MatchExactly '100'
                $rows[0].Right | Should -MatchExactly '20'
            }
        }

        It "別の列への差し替えは Changed にしない" {
            InModuleScope TextDiff {
                # 削除と追加がたまたま隣り合っただけ。対にすると行全体が強調されて読めなくなる
                $rows = @(Get-DiffAlignment -BeforeLines @('    status_code character(2) NOT NULL,') -AfterLines @('    contact_email_address text,'))

                Get-Shape -Rows $rows | Should -BeExactly 'Deleted:1>- Added:->1'
            }
        }

        It "書き換えと、無関係な削除・追加が混在しても取り違えない" {
            InModuleScope TextDiff {
                # 1つのテーブルで桁変更・列削除・列追加が同時に起きた場合。
                # 1つのテーブルで桁変更・列削除・列追加が同時に起きた場合
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

        It "しきい値を上げれば対にしなくなる" {
            InModuleScope TextDiff {
                # 判定が本当にしきい値で動いていることの確認
                # NOTE: $args は自動変数。splat 用の名前に使うと lint に弾かれる
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

        It "削除の方が多い場合、余った分は Deleted のまま残す" {
            InModuleScope TextDiff {
                $before = @('aaa1', 'aaa2', 'aaa3')
                $after = @('aaa9')

                $rows = @(Get-DiffAlignment -BeforeLines $before -AfterLines $after)

                @($rows | Where-Object -FilterScript { $_.Kind -ceq 'Changed' }).Count | Should -BeExactly 1
                @($rows | Where-Object -FilterScript { $_.Kind -ceq 'Deleted' }).Count | Should -BeExactly 2
            }
        }

        It "追加の方が多い場合、余った分は Added のまま残す" {
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
                # 描画側が「反対側に対応する行が無い」を斜線で示すための情報
                $rows = @(Get-DiffAlignment -BeforeLines @('a') -AfterLines @('b'))

                ($rows | Where-Object -FilterScript { $_.Kind -ceq 'Deleted' }).Right | Should -BeNullOrEmpty
                ($rows | Where-Object -FilterScript { $_.Kind -ceq 'Deleted' }).RightNo | Should -BeNullOrEmpty
                ($rows | Where-Object -FilterScript { $_.Kind -ceq 'Added' }).Left | Should -BeNullOrEmpty
                ($rows | Where-Object -FilterScript { $_.Kind -ceq 'Added' }).LeftNo | Should -BeNullOrEmpty
            }
        }

        It "内部で使う Order を戻り値に残さない" {
            InModuleScope TextDiff {
                # 並べ替え用の一時項目。呼び出し側に見えると、描画が依存してしまう
                $rows = @(Get-DiffAlignment -BeforeLines @('a', 'b') -AfterLines @('x', 'y'))

                foreach ($row in $rows) {
                    $row.ContainsKey('Order') | Should -BeFalse
                }
            }
        }
    }

    Context "実際のスナップショットに近い規模" {

        It "1000行のうち数行だけ変わっている場合を現実的な時間で処理する" {
            InModuleScope TextDiff {
                # 素朴な動的計画法では約 2.8 秒かかる規模（実測）。
                # Myers 法を使う理由が失われていないことを守る
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
