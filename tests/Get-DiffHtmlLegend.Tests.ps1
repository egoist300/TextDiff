#Requires -Version 5.1

BeforeAll {
    Set-StrictMode -Version 3.0
    # 非公開の関数はモジュールの中からしか呼び出せない。ファイルごとに読み込み直すため、前のファイルが定義した関数は残らない。
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\TextDiff\TextDiff.psd1') -Force
}

Describe "Get-DiffHtmlLegend" {

    It "凡例は配色の意味を文字でも示す" {
        InModuleScope TextDiff {
            # 色の区別がしにくい環境でも読めるようにするため。
            $legend = Get-DiffHtmlLegend

            $legend | Should -Not -BeNullOrEmpty
            $legend | Should -MatchExactly '削除|追加'
        }
    }

    It "凡例は差分マップの見方と操作を説明する" {
        InModuleScope TextDiff {
            # 差分マップには見出しが無く、説明が無いと、クリックで移動できることに気づけないため。
            Get-DiffHtmlLegend | Should -MatchExactly '右端の帯.*クリック'
        }
    }

}

AfterAll {
    Remove-Module -Name TextDiff -ErrorAction SilentlyContinue
}
