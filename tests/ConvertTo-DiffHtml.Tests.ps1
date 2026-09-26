# 横並べ HTML 出力のテスト。
#
# 最も重視するのはエスケープ。スナップショットには COMMENT やデータがそのまま入り、
# < > & が含まれることは普通にある。エスケープを忘れると表示が壊れるだけでなく、
# 内容がタグとして解釈されて黙って消える。証跡が欠けるので正しさの問題として扱う。
#
# 次に、左右のペインの行数が揃っていること。揃わないと行が上下にずれ、
# 横並べにした意味そのものが消える。

BeforeAll {
    # テストのコード自身も StrictMode 3.0 で動かす。モジュールの中は TextDiff.psm1 が設定している
    Set-StrictMode -Version 3.0
    # テスト対象はモジュールとして読み込み、テストの中身はモジュールの中（InModuleScope）で動かす。
    # 非公開の関数はモジュールの中からしか呼べない。ファイルごとに読み直すので、前のファイルが置いた関数は残らない
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\TextDiff\TextDiff.psd1') -Force
    InModuleScope TextDiff {
        function script:New-Section {
            <#
            .SYNOPSIS
                ConvertTo-DiffHtml に渡すセクションを 1 つ作る。
            .PARAMETER Label
                セクションの見出し。
            .PARAMETER Before
                変更前の行の並び。
            .PARAMETER After
                変更後の行の並び。
            #>
            param([string]$Label = 'テーブル定義', [string[]]$Before, [string[]]$After)
            return @{ Label = $Label; Rows = @(Get-DiffAlignment -BeforeLines $Before -AfterLines $After) }
        }

        # ペインごとの <tr> の数を数える
        function script:Get-RowCount {
            <#
            .SYNOPSIS
                HTML の片側のペインにある行（<tr>）の数を返す。ペインが無ければ -1。
            .PARAMETER Html
                ConvertTo-DiffHtml が返した HTML。
            .PARAMETER Side
                数えるペイン（'left' か 'right'）。
            #>
            param([string]$Html, [string]$Side)
            $paneStart = $Html.IndexOf("<div class=""pane $Side"">", [System.StringComparison]::Ordinal)
            if ($paneStart -lt 0) { return -1 }
            $paneEnd = $Html.IndexOf('</table>', $paneStart, [System.StringComparison]::Ordinal)
            $pane = $Html.Substring($paneStart, ($paneEnd - $paneStart))
            return ([regex]::Matches($pane, '<tr')).Count
        }
    }
}

Describe "ConvertTo-DiffHtml" {

    Context "文書としての体裁" {

        It "文字コードを宣言する" {
            InModuleScope TextDiff {
                # 宣言が無いとブラウザの推測に委ねられ、日本語が化ける
                $html = ConvertTo-DiffHtml -Title 'T' -Sections @(New-Section -Before @('a') -After @('b'))

                $html | Should -MatchExactly '<meta charset="utf-8">'
            }
        }

        It "CSS と JavaScript を埋め込む（外部を参照しない）" {
            InModuleScope TextDiff {
                # 証跡フォルダを別のマシンにコピーしても表示が崩れないようにするため
                $html = ConvertTo-DiffHtml -Title 'T' -Sections @(New-Section -Before @('a') -After @('b'))

                $html | Should -MatchExactly '<style>'
                $html | Should -MatchExactly '<script>'
                $html | Should -Not -MatchExactly '<link[^>]+href'
                $html | Should -Not -MatchExactly '<script[^>]+src='
            }
        }

        It "見出しもエスケープする" {
            InModuleScope TextDiff {
                $html = ConvertTo-DiffHtml -Title 'DDL_<test>' -Sections @(New-Section -Before @('a') -After @('b'))

                $html | Should -MatchExactly 'DDL_&lt;test&gt;'
                $html | Should -Not -MatchExactly '<title>DDL_<test>'
            }
        }

        It "凡例を含める" {
            InModuleScope TextDiff {
                # 証跡は差分ツールに慣れていない人も読む。色だけで意味を察してもらわない
                $html = ConvertTo-DiffHtml -Title 'T' -Sections @(New-Section -Before @('a') -After @('b'))

                $html | Should -MatchExactly '削除された行'
                $html | Should -MatchExactly '追加された行'
                $html | Should -MatchExactly '行内で変わった部分'
                $html | Should -MatchExactly '反対側に対応する行が無い'
            }
        }
    }

    Context "内容の埋め込み" {

        It "データに含まれる HTML をタグとして解釈させない" {
            InModuleScope TextDiff {
                # COMMENT や text 型の値に < > が入るのは普通にある。
                # 素通しすると証跡が黙って消える
                $html = ConvertTo-DiffHtml -Title 'T' -Sections @(
                    New-Section -Before @('remarks text, -- <script>alert(1)</script>') -After @('remarks text,')
                )

                $html | Should -Not -MatchExactly '<script>alert'
                $html | Should -MatchExactly '&lt;script&gt;alert'
            }
        }

        It "書き換えた行の変わった部分を強調する" {
            InModuleScope TextDiff {
                $html = ConvertTo-DiffHtml -Title 'T' -Sections @(
                    New-Section -Before @('    name character varying(100),') -After @('    name character varying(20),')
                )

                $html | Should -MatchExactly '<b>100</b>'
                $html | Should -MatchExactly '<b>20</b>'
            }
        }

        It "対にならない削除・追加には強調を付けない" {
            InModuleScope TextDiff {
                $html = ConvertTo-DiffHtml -Title 'T' -Sections @(
                    New-Section -Before @('    status_code character(2),') -After @('    email text,')
                )

                $html | Should -Not -MatchExactly '<b>'
            }
        }
    }

    Context "左右のペイン" {

        It "左右の行数が一致する" {
            InModuleScope TextDiff {
                # 揃わないと行が上下にずれ、横並べにした意味が消える
                $html = ConvertTo-DiffHtml -Title 'T' -Sections @(
                    New-Section -Before @('a', 'b', 'c', 'd') -After @('a', 'x', 'd', 'e', 'f')
                )

                $left = Get-RowCount -Html $html -Side 'left'
                $right = Get-RowCount -Html $html -Side 'right'
                $left | Should -BeGreaterThan 0
                $left | Should -BeExactly $right
            }
        }

        It "反対側に無い行は空欄にする（斜線を当てるため）" {
            InModuleScope TextDiff {
                $html = ConvertTo-DiffHtml -Title 'T' -Sections @(
                    New-Section -Before @('a') -After @('a', 'b')
                )

                $html | Should -MatchExactly 'class="tx empty"'
            }
        }

        It "行番号を出す" {
            InModuleScope TextDiff {
                # 「どこの差分か」を位置で示す。行番号が無いと、差分の場所を元のファイルで探せない
                $html = ConvertTo-DiffHtml -Title 'T' -Sections @(
                    New-Section -Before @('a', 'b') -After @('a', 'c')
                )

                $html | Should -MatchExactly '<td class="ln">2</td>'
            }
        }
    }

    Context "差分なし・検証不能" {

        It "差分が無いセクションは (差分なし) と出す" {
            InModuleScope TextDiff {
                $html = ConvertTo-DiffHtml -Title 'T' -Sections @(New-Section -Before @('a') -After @('a'))

                $html | Should -MatchExactly '\(差分なし\)'
                $html | Should -Not -MatchExactly 'class="panes"'
            }
        }

        It "検証不能のセクションは理由を出し、差分を出さない" {
            InModuleScope TextDiff {
                # 「差分なし」と見分けが付かない表示にしてはならない。
                # 何も検証できていない実行を「変更なし」と読ませるのが最悪の結果
                $html = ConvertTo-DiffHtml -Title 'T' -Sections @(
                    @{ Label = 'テーブル定義'; Rows = @(); Unverified = @('!!! 検証不能: before の取得に失敗 !!!') }
                )

                $html | Should -MatchExactly '検証不能'
                $html | Should -Not -MatchExactly '\(差分なし\)'
                $html | Should -Not -MatchExactly 'class="panes"'
            }
        }

        It "検証不能の理由もエスケープする" {
            InModuleScope TextDiff {
                $html = ConvertTo-DiffHtml -Title 'T' -Sections @(
                    @{ Label = 'L'; Rows = @(); Unverified = @('ERROR: relation "<x>" does not exist') }
                )

                $html | Should -MatchExactly '&lt;x&gt;'
            }
        }
    }

    Context "複数セクション" {

        It "セクションの数だけカードを作る" {
            InModuleScope TextDiff {
                $html = ConvertTo-DiffHtml -Title 'T' -Sections @(
                    New-Section -Label 'テーブル定義' -Before @('a') -After @('b')
                    New-Section -Label 'カラム一覧' -Before @('c') -After @('d')
                )

                ([regex]::Matches($html, 'class="card-head"')).Count | Should -BeExactly 2
                $html | Should -MatchExactly 'テーブル定義'
                $html | Should -MatchExactly 'カラム一覧'
            }
        }

        It "セクションが1つも無くても文書として成立する" {
            InModuleScope TextDiff {
                $html = ConvertTo-DiffHtml -Title 'T' -Sections @()

                $html | Should -MatchExactly '</html>'
            }
        }
    }

    Context "受け付ける入力" {

        It "Rows に Get-DiffAlignment の結果ではないものを渡すと失敗する" {
            InModuleScope TextDiff {
                # 差分の無い行（Same）だけだと行を描かないので、描くときの型の検査は通らない。入口で弾くことを確かめる
                $section = @{ Label = 'L'; Rows = @(@{ Kind = 'Same'; LeftNo = 1; RightNo = 1; Left = 'a'; Right = 'a' }) }

                { ConvertTo-DiffHtml -Title 'T' -Sections @($section) } | Should -Throw -ExceptionType ([System.ArgumentException])
            }
        }
    }
}

AfterAll {
    Remove-Module -Name TextDiff -ErrorAction SilentlyContinue
}
