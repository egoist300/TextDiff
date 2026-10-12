#Requires -Version 5.1

# Get-DiffHtmlMap のテスト。

BeforeAll {
    # テストのコード自身も StrictMode 3.0 で実行する。モジュールの中は TextDiff.psm1 が設定する。
    Set-StrictMode -Version 3.0
    # テスト対象はモジュールとして読み込み、テストはモジュールの中（InModuleScope）で実行する。
    # 非公開の関数はモジュールの中からしか呼び出せない。ファイルごとに読み込み直すため、前のファイルが定義した関数は残らない。
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\TextDiff\TextDiff.psd1') -Force
}

Describe "Get-DiffHtmlMap" {

    It "印の位置と高さは、全体の行数に対する割合で示す" {
        InModuleScope TextDiff {
            $rows = @(Get-DiffAlignment -BeforeLines @('a', 'b', 'c', 'd') -AfterLines @('a', 'b', 'c', 'd', 'e'))

            Get-DiffHtmlMap -Rows $rows | Should -MatchExactly '<i class="a" style="top: 80%; height: 20%"></i>'
        }
    }

    It "連続する同じ種類の行は 1 つの印にまとめる" {
        InModuleScope TextDiff {
            # 行ごとに印を出力すると、1000 行の追加で 1000 個の要素になるため。
            $rows = @(Get-DiffAlignment -BeforeLines @('a') -AfterLines @('a', 'b', 'c'))

            $map = Get-DiffHtmlMap -Rows $rows

            ([regex]::Matches($map, '<i ')).Count | Should -BeExactly 1
            $map | Should -MatchExactly 'top: 33\.333%; height: 66\.667%'
        }
    }

    It "変更・削除・追加の印は、凡例と同じクラスで区別する" {
        InModuleScope TextDiff {
            $rows = @(Get-DiffAlignment -BeforeLines @('id bigint,', 'name varchar(100),', 'note text,') -AfterLines @('id bigint,', 'name varchar(20),'))
            $addedRows = @(Get-DiffAlignment -BeforeLines @('a') -AfterLines @('a', 'b'))

            $map = Get-DiffHtmlMap -Rows $rows

            $map | Should -MatchExactly '<i class="m" style="top: 33\.333%'
            $map | Should -MatchExactly '<i class="d" style="top: 66\.667%'
            Get-DiffHtmlMap -Rows $addedRows | Should -MatchExactly '<i class="a" '
        }
    }

    It "小数点にカンマを使うカルチャーでも、割合は CSS として解釈できる形で出力する" {
        InModuleScope TextDiff {
            $rows = @(Get-DiffAlignment -BeforeLines @('a') -AfterLines @('a', 'b', 'c'))
            $originalCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
            try {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo('de-DE')
                $map = Get-DiffHtmlMap -Rows $rows
            }
            finally {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = $originalCulture
            }

            $map | Should -MatchExactly 'top: 33\.333%'
        }
    }

    It "差分の無い行には印を出力しない" {
        InModuleScope TextDiff {
            $rows = @(Get-DiffAlignment -BeforeLines @('a', 'b') -AfterLines @('a', 'b'))

            Get-DiffHtmlMap -Rows $rows | Should -Not -MatchExactly '<i '
            { Get-DiffHtmlMap -Rows @() } | Should -Not -Throw
        }
    }

}

AfterAll {
    Remove-Module -Name TextDiff -ErrorAction SilentlyContinue
}
