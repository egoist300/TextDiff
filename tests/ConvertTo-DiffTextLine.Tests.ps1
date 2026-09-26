#Requires -Version 5.1

# ConvertTo-DiffTextLine のテスト。

BeforeAll {
    # テストのコード自身も StrictMode 3.0 で実行する。モジュールの中は TextDiff.psm1 が設定する。
    Set-StrictMode -Version 3.0
    # テスト対象はモジュールとして読み込み、テストはモジュールの中（InModuleScope）で実行する。
    # 非公開の関数はモジュールの中からしか呼び出せない。ファイルごとに読み込み直すため、前のファイルが定義した関数は残らない。
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\TextDiff\TextDiff.psd1') -Force
}

Describe "ConvertTo-DiffTextLine" {

    It "行は型名 TextDiff.TextLine で、項目は Gutter, Role, Segments, OmittedCount の順" {
        InModuleScope TextDiff {
            $line = ConvertTo-DiffTextLine -Gutter '    1  ' -Role 'Context' -Text 'a'

            $line.PSObject.TypeNames[0] | Should -BeExactly 'TextDiff.TextLine'
            (@($line.PSObject.Properties | ForEach-Object -Process { $_.Name }) -join ',') | Should -BeExactly 'Gutter,Role,Segments,OmittedCount'
        }
    }

    It "Text を渡すと、行全体を 1 つの共通部分の断片にする" {
        InModuleScope TextDiff {
            $line = ConvertTo-DiffTextLine -Gutter '    1  ' -Role 'Context' -Text 'abc'

            @($line.Segments).Count | Should -BeExactly 1
            $line.Segments[0].PSObject.TypeNames[0] | Should -BeExactly 'TextDiff.Segment'
            $line.Segments[0].Text | Should -BeExactly 'abc'
            $line.Segments[0].Changed | Should -BeFalse
            $line.OmittedCount | Should -BeExactly 0
        }
    }

    It "空行の Text も受け取る" {
        InModuleScope TextDiff {
            # 比較する行には空行が含まれるため。
            $line = ConvertTo-DiffTextLine -Gutter '    1  ' -Role 'Context' -Text ''

            $line.Segments[0].Text | Should -BeExactly ''
        }
    }

    It "Segments を渡すと、そのまま断片にする" {
        InModuleScope TextDiff {
            $segments = @(Join-DiffSegment -Segments @(@{ Text = 'a'; Changed = $false }, @{ Text = 'b'; Changed = $true }))

            $line = ConvertTo-DiffTextLine -Gutter '    1- ' -Role 'Removed' -Segments $segments

            @($line.Segments | ForEach-Object -Process { $_.Text }) | Should -BeExactly @('a', 'b')
        }
    }

    It "省略行は断片を持たず、省略した行数を持つ" {
        InModuleScope TextDiff {
            $line = ConvertTo-DiffTextLine -Gutter '  ...  ' -Role 'Omitted' -OmittedCount 23

            @($line.Segments).Count | Should -BeExactly 0
            $line.OmittedCount | Should -BeExactly 23
        }
    }

    It "Text と Segments は同時に渡せない" {
        InModuleScope TextDiff {
            { ConvertTo-DiffTextLine -Gutter ' ' -Role 'Context' -Text 'a' -Segments @() } | Should -Throw -ErrorId 'AmbiguousParameterSet,ConvertTo-DiffTextLine'
        }
    }
}

AfterAll {
    Remove-Module -Name TextDiff -ErrorAction SilentlyContinue
}
