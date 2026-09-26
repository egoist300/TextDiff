# Join-DiffSegment のテスト。

BeforeAll {
    # テストのコード自身も StrictMode 3.0 で動かす。モジュールの中は TextDiff.psm1 が設定している
    Set-StrictMode -Version 3.0
    # テスト対象はモジュールとして読み込み、テストの中身はモジュールの中（InModuleScope）で動かす。
    # 非公開の関数はモジュールの中からしか呼べない。ファイルごとに読み直すので、前のファイルが置いた関数は残らない
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\TextDiff\TextDiff.psd1') -Force
}

Describe "Join-DiffSegment" {

    It "隣り合う同じ状態をつなげる" {
        InModuleScope TextDiff {
            # つなげないと、変わっていない部分がトークンの数だけ細切れになり、
            # コンソールでは Write-Host の回数がそのまま増えて遅くなる
            $merged = @(Join-DiffSegment -Segments @(
                    @{ Text = 'a'; Changed = $false }
                    @{ Text = 'b'; Changed = $false }
                    @{ Text = 'c'; Changed = $true }
                ))

            $merged.Count | Should -BeExactly 2
            $merged[0].Text | Should -BeExactly 'ab'
            $merged[1].Text | Should -BeExactly 'c'
        }
    }

    It "空文字の断片は捨てる" {
        InModuleScope TextDiff {
            $merged = @(Join-DiffSegment -Segments @(
                    @{ Text = ''; Changed = $false }
                    @{ Text = 'a'; Changed = $true }
                ))

            $merged.Count | Should -BeExactly 1
            $merged[0].Text | Should -BeExactly 'a'
        }
    }

    It "すべて空なら空の配列" {
        InModuleScope TextDiff {
            @(Join-DiffSegment -Segments @(@{ Text = ''; Changed = $false })).Count | Should -BeExactly 0
        }
    }

    It "断片は型名 TextDiff.Segment の PSCustomObject で返す" {
        InModuleScope TextDiff {
            # この断片は ConvertTo-DiffText の戻り値として利用者に渡る
            $merged = @(Join-DiffSegment -Segments @(@{ Text = 'a'; Changed = $false }, @{ Text = 'b'; Changed = $true }))

            foreach ($segment in $merged) {
                $segment -is [System.Management.Automation.PSCustomObject] | Should -BeTrue
                $segment.PSObject.TypeNames[0] | Should -BeExactly 'TextDiff.Segment'
                (@($segment.PSObject.Properties | ForEach-Object -Process { $_.Name }) -join ',') | Should -BeExactly 'Text,Changed'
            }
        }
    }
}

AfterAll {
    Remove-Module -Name TextDiff -ErrorAction SilentlyContinue
}
