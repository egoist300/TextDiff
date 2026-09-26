#Requires -Version 5.1

# ConvertTo-DiffHtml のテスト。
#
# 最も重視するのはエスケープ。比較する行には < > & が含まれることがあり、エスケープが漏れると
# 表示が崩れるだけでなく、内容がタグとして解釈されて表示されない。
# 差分の内容が欠落するため、正しさの問題として扱う。
#
# 次に重視するのは、左右のペインの行数が一致すること。一致しないと行が上下にずれ、
# 左右を比較できない。

BeforeAll {
    # テストのコード自身も StrictMode 3.0 で実行する。モジュールの中は TextDiff.psm1 が設定する。
    Set-StrictMode -Version 3.0
    # テスト対象はモジュールとして読み込み、テストはモジュールの中（InModuleScope）で実行する。
    # 非公開の関数はモジュールの中からしか呼び出せない。ファイルごとに読み込み直すため、前のファイルが定義した関数は残らない。
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\TextDiff\TextDiff.psd1') -Force
    InModuleScope TextDiff {
        function script:New-Section {
            <#
            .SYNOPSIS
                ConvertTo-DiffHtml に渡すセクションを 1 つ作成する。
            .PARAMETER Label
                セクションの見出し。
            .PARAMETER Before
                変更前の行の配列。
            .PARAMETER After
                変更後の行の配列。
            #>
            param([string]$Label = 'アプリ設定', [string[]]$Before, [string[]]$After)
            return @{ Label = $Label; Rows = @(Get-DiffAlignment -BeforeLines $Before -AfterLines $After) }
        }

        function script:Get-RowCount {
            <#
            .SYNOPSIS
                HTML の片側のペインにある行（<tr>）の数を返す。ペインが無ければ -1。
            .PARAMETER Html
                ConvertTo-DiffHtml が返した HTML。
            .PARAMETER Side
                対象のペイン（'left' か 'right'）。
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

    Context "HTML 文書の構成" {

        It "文字コードを宣言する" {
            InModuleScope TextDiff {
                # 宣言が無いと文字コードの判定がブラウザに任され、日本語が文字化けするため。
                $html = ConvertTo-DiffHtml -Title 'T' -Sections @(New-Section -Before @('a') -After @('b'))

                $html | Should -MatchExactly '<meta charset="utf-8">'
            }
        }

        It "CSS と JavaScript を埋め込む（外部を参照しない）" {
            InModuleScope TextDiff {
                # HTML ファイルを別のマシンにコピーしても、表示が崩れないようにするため。
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
                # 差分ツールに慣れていない人も HTML を読むため、配色だけで意味が伝わる前提にしない。
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
                # 比較する行には < > が含まれることがある。エスケープしないと、内容がタグとして解釈されて表示されないため。
                $html = ConvertTo-DiffHtml -Title 'T' -Sections @(
                    New-Section -Before @('remarks text, -- <script>alert(1)</script>') -After @('remarks text,')
                )

                $html | Should -Not -MatchExactly '<script>alert'
                $html | Should -MatchExactly '&lt;script&gt;alert'
            }
        }

        It "変更行の変更箇所を強調する" {
            InModuleScope TextDiff {
                $html = ConvertTo-DiffHtml -Title 'T' -Sections @(
                    New-Section -Before @('    name character varying(100),') -After @('    name character varying(20),')
                )

                $html | Should -MatchExactly '<b>100</b>'
                $html | Should -MatchExactly '<b>20</b>'
            }
        }

        It "対応付けていない削除行と追加行は強調しない" {
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
                # 行数が一致しないと行が上下にずれ、左右を比較できないため。
                $html = ConvertTo-DiffHtml -Title 'T' -Sections @(
                    New-Section -Before @('a', 'b', 'c', 'd') -After @('a', 'x', 'd', 'e', 'f')
                )

                $left = Get-RowCount -Html $html -Side 'left'
                $right = Get-RowCount -Html $html -Side 'right'
                $left | Should -BeGreaterThan 0
                $left | Should -BeExactly $right
            }
        }

        It "反対側に無い行は空欄にする（斜線を表示するため）" {
            InModuleScope TextDiff {
                $html = ConvertTo-DiffHtml -Title 'T' -Sections @(
                    New-Section -Before @('a') -After @('a', 'b')
                )

                $html | Should -MatchExactly 'class="tx empty"'
            }
        }

        It "行番号を表示する" {
            InModuleScope TextDiff {
                # 行番号が無いと、差分の位置を元のファイルで特定できないため。
                $html = ConvertTo-DiffHtml -Title 'T' -Sections @(
                    New-Section -Before @('a', 'b') -After @('a', 'c')
                )

                $html | Should -MatchExactly '<td class="ln">2</td>'
            }
        }
    }

    Context "差分なし・検証不能" {

        It "差分が無いセクションは (差分なし) と表示する" {
            InModuleScope TextDiff {
                $html = ConvertTo-DiffHtml -Title 'T' -Sections @(New-Section -Before @('a') -After @('a'))

                $html | Should -MatchExactly '\(差分なし\)'
                $html | Should -Not -MatchExactly 'class="panes"'
            }
        }

        It "検証不能のセクションは理由を表示し、差分を表示しない" {
            InModuleScope TextDiff {
                # 「差分なし」と区別できない表示にしない。
                # 検証できていない実行を「変更なし」と誤読させることが、最も避けるべき結果のため。
                $html = ConvertTo-DiffHtml -Title 'T' -Sections @(
                    @{ Label = 'アプリ設定'; Rows = @(); Unverified = @('!!! 検証不能: before の取得に失敗 !!!') }
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

        It "セクションの数だけカードを作成する" {
            InModuleScope TextDiff {
                $html = ConvertTo-DiffHtml -Title 'T' -Sections @(
                    New-Section -Label 'アプリ設定' -Before @('a') -After @('b')
                    New-Section -Label '接続設定' -Before @('c') -After @('d')
                )

                ([regex]::Matches($html, 'class="card-head"')).Count | Should -BeExactly 2
                $html | Should -MatchExactly 'アプリ設定'
                $html | Should -MatchExactly '接続設定'
            }
        }

        It "セクションが 1 つも無くても HTML 文書として成立する" {
            InModuleScope TextDiff {
                $html = ConvertTo-DiffHtml -Title 'T' -Sections @()

                $html | Should -MatchExactly '</html>'
            }
        }
    }

    Context "受け付ける入力" {

        It "Rows に Get-DiffAlignment の結果ではないものを渡すと失敗する" {
            InModuleScope TextDiff {
                # 差分の無い行（Same）だけでは行を出力しないため、出力時の型の検証を経由しない。関数の入口で拒否することを確認する。
                $section = @{ Label = 'L'; Rows = @(@{ Kind = 'Same'; LeftNo = 1; RightNo = 1; Left = 'a'; Right = 'a' }) }

                { ConvertTo-DiffHtml -Title 'T' -Sections @($section) } | Should -Throw -ExceptionType ([System.ArgumentException])
            }
        }
    }
}

AfterAll {
    Remove-Module -Name TextDiff -ErrorAction SilentlyContinue
}
