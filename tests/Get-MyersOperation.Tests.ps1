#Requires -Version 5.1

# Get-MyersOperation のテスト。

BeforeAll {
    # テストのコード自身も StrictMode 3.0 で動かす。モジュールの中は TextDiff.psm1 が設定している
    Set-StrictMode -Version 3.0
    # テスト対象はモジュールとして読み込み、テストの中身はモジュールの中（InModuleScope）で動かす。
    # 非公開の関数はモジュールの中からしか呼べない。ファイルごとに読み直すので、前のファイルが置いた関数は残らない
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\TextDiff\TextDiff.psd1') -Force
}

Describe "Get-MyersOperation" {

    # 差分エンジンの心臓部。行 ID の列を突き合わせて Same/Deleted/Added の並びを返す。
    # ここが崩れると、対応づけも行番号も行内強調も全部ずれる。
    # Get-DiffAlignment 経由でも通るが、境界だけは直接固定しておく

    It "同一なら全部 Same" {
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

    It "before が空なら全部 Added（新規作成）" {
        InModuleScope TextDiff {
            # 作成前のスナップショットは空。ここを Deleted にすると証跡が逆になる
            $ops = @(Get-MyersOperation -Left @() -Right @(1, 2))

            $ops.Count | Should -BeExactly 2
            @($ops | Where-Object -FilterScript { $_.Kind -ceq 'Added' }).Count | Should -BeExactly 2
            @($ops | ForEach-Object -Process { $_.LeftIndex }) | Should -BeExactly @($null, $null)
        }
    }

    It "after が空なら全部 Deleted（削除）" {
        InModuleScope TextDiff {
            $ops = @(Get-MyersOperation -Left @(1, 2) -Right @())

            @($ops | Where-Object -FilterScript { $_.Kind -ceq 'Deleted' }).Count | Should -BeExactly 2
        }
    }

    It "添字は元の位置を指す" {
        InModuleScope TextDiff {
            # 行番号の表示と行内強調がこの添字に乗る。ずれると別の行を強調する
            $ops = @(Get-MyersOperation -Left @(1, 2, 3) -Right @(1, 3))

            foreach ($op in $ops) {
                if ($null -ne $op.LeftIndex) { $op.LeftIndex | Should -BeGreaterOrEqual 0; $op.LeftIndex | Should -BeLessThan 3 }
                if ($null -ne $op.RightIndex) { $op.RightIndex | Should -BeGreaterOrEqual 0; $op.RightIndex | Should -BeLessThan 2 }
            }
        }
    }

    It "共通部分を最大にする（削除と追加を並べるだけにしない）" {
        InModuleScope TextDiff {
            # ここが効かないと「1行変わっただけ」が「全消し・全追加」になる
            $ops = @(Get-MyersOperation -Left @(1, 2, 3) -Right @(1, 9, 3))

            @($ops | Where-Object -FilterScript { $_.Kind -ceq 'Same' }).Count | Should -BeExactly 2
        }
    }

    It "先頭への挿入を Same の前に置く" {
        InModuleScope TextDiff {
            $ops = @(Get-MyersOperation -Left @(2) -Right @(1, 2))

            $ops[0].Kind | Should -BeExactly 'Added'
            $ops[1].Kind | Should -BeExactly 'Same'
        }
    }

    It "Same は両側の添字を持つ" {
        InModuleScope TextDiff {
            # 片方が $null だと、対応づけた相手の行番号を出せない
            $ops = @(Get-MyersOperation -Left @(7) -Right @(7))

            $ops[0].LeftIndex | Should -BeExactly 0
            $ops[0].RightIndex | Should -BeExactly 0
        }
    }
}

AfterAll {
    Remove-Module -Name TextDiff -ErrorAction SilentlyContinue
}
