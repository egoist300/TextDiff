#Requires -Version 5.1

# Get-MyersOperation のテスト。

BeforeAll {
    # テストのコード自身も StrictMode 3.0 で実行する。モジュールの中は TextDiff.psm1 が設定する。
    Set-StrictMode -Version 3.0
    # テスト対象はモジュールとして読み込み、テストはモジュールの中（InModuleScope）で実行する。
    # 非公開の関数はモジュールの中からしか呼び出せない。ファイルごとに読み込み直すため、前のファイルが定義した関数は残らない。
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\TextDiff\TextDiff.psd1') -Force
}

Describe "Get-MyersOperation" {

    # 差分計算の中核。この関数の結果が誤ると、行の対応付けも行番号も行内の強調もすべてずれる。
    # Get-DiffAlignment 経由でも確認できるが、境界の条件は直接確認する。

    It "同一なら、すべて Same" {
        InModuleScope TextDiff {
            $ops = @(Get-MyersOperation -Left @(1, 2, 3) -Right @(1, 2, 3))

            $ops.Count | Should -BeExactly 3
            @($ops | Where-Object -FilterScript { $_.Kind -cne 'Same' }).Count | Should -BeExactly 0
        }
    }

    It "両方空なら操作も空" {
        InModuleScope TextDiff {
            @(Get-MyersOperation -Left @() -Right @()).Count | Should -BeExactly 0
        }
    }

    It "変更前が空なら、すべて Added（新規作成）" {
        InModuleScope TextDiff {
            # 新規作成の場合、変更前は空。Deleted にすると差分の向きが逆になるため。
            $ops = @(Get-MyersOperation -Left @() -Right @(1, 2))

            $ops.Count | Should -BeExactly 2
            @($ops | Where-Object -FilterScript { $_.Kind -ceq 'Added' }).Count | Should -BeExactly 2
            @($ops | ForEach-Object -Process { $_.LeftIndex }) | Should -BeExactly @($null, $null)
        }
    }

    It "変更後が空なら、すべて Deleted（削除）" {
        InModuleScope TextDiff {
            $ops = @(Get-MyersOperation -Left @(1, 2) -Right @())

            @($ops | Where-Object -FilterScript { $_.Kind -ceq 'Deleted' }).Count | Should -BeExactly 2
        }
    }

    It "添字は元の位置を指す" {
        InModuleScope TextDiff {
            # 行番号の表示と行内の強調はこの添字を使う。ずれると別の行を強調するため。
            $ops = @(Get-MyersOperation -Left @(1, 2, 3) -Right @(1, 3))

            foreach ($op in $ops) {
                if ($null -ne $op.LeftIndex) { $op.LeftIndex | Should -BeGreaterOrEqual 0; $op.LeftIndex | Should -BeLessThan 3 }
                if ($null -ne $op.RightIndex) { $op.RightIndex | Should -BeGreaterOrEqual 0; $op.RightIndex | Should -BeLessThan 2 }
            }
        }
    }

    It "共通部分を最大にする（削除と追加を並べるだけにしない）" {
        InModuleScope TextDiff {
            # 共通行を検出できないと、1 行の変更が「全行の削除と全行の追加」になるため。
            $ops = @(Get-MyersOperation -Left @(1, 2, 3) -Right @(1, 9, 3))

            @($ops | Where-Object -FilterScript { $_.Kind -ceq 'Same' }).Count | Should -BeExactly 2
        }
    }

    It "先頭への挿入を Same の前に配置する" {
        InModuleScope TextDiff {
            $ops = @(Get-MyersOperation -Left @(2) -Right @(1, 2))

            $ops[0].Kind | Should -BeExactly 'Added'
            $ops[1].Kind | Should -BeExactly 'Same'
        }
    }

    It "Same は両側の添字を持つ" {
        InModuleScope TextDiff {
            # 片方が $null だと、対応付けた行の行番号を表示できないため。
            $ops = @(Get-MyersOperation -Left @(7) -Right @(7))

            $ops[0].LeftIndex | Should -BeExactly 0
            $ops[0].RightIndex | Should -BeExactly 0
        }
    }
}

AfterAll {
    Remove-Module -Name TextDiff -ErrorAction SilentlyContinue
}
