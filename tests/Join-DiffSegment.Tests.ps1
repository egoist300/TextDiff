#Requires -Version 5.1

# Join-DiffSegment のテスト。

BeforeAll {
    # テストのコード自身も StrictMode 3.0 で実行する。モジュールの中は TextDiff.psm1 が設定する。
    Set-StrictMode -Version 3.0
    # テスト対象はモジュールとして読み込み、テストはモジュールの中（InModuleScope）で実行する。
    # 非公開の関数はモジュールの中からしか呼び出せない。ファイルごとに読み込み直すため、前のファイルが定義した関数は残らない。
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\TextDiff\TextDiff.psd1') -Force
}

Describe "Join-DiffSegment" {

    It "隣接する同じ状態の断片を結合する" {
        InModuleScope TextDiff {
            # 結合しないと、共通部分がトークンの数だけの細かい断片になり、
            # コンソールでは Write-Host の呼び出し回数が増えて遅くなるため。
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

    It "空文字の断片は除外する" {
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
            # この断片は ConvertTo-DiffText の戻り値として利用者に渡るため。
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
