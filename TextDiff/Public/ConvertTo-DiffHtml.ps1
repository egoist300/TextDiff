# 対応づけの結果を、左右に並べた HTML に変換する処理。
#
# 【なぜ HTML か】
# - と + を並べる表示では、どこが差分か分かりにくい。
# 削除行を全部並べてから追加行を全部並べる形では、どれとどれが対なのかが読めない。
# 左右に置いて片方にしか無い行を斜線にすれば、変更・削除・追加が位置で区別できる。
#
# 【コンソール表示と役割が違う】
# コンソールは、作業中の人がその場で次へ進むか判断するためのもの。
# こちらは後から証跡を読む人（レビュー・監査・障害調査）のためのもので、
# 端末幅の制約が無く、色も横スクロールも使える。だから表現が違ってよい。
# コンソール側は文脈行を畳むが、こちらは畳まない（証跡としては全体が残る方がよい）。
#
# 【生成物は 1 ファイルで完結させる】
# CSS も JavaScript も埋め込む。証跡フォルダを別のマシンにコピーしても
# 表示が崩れないようにするため。外部から何も読み込まない。

function ConvertTo-DiffHtml {
    <#
    .SYNOPSIS
        セクションごとの対応づけ結果を、1 つの HTML 文書に変換する。
    .DESCRIPTION
        セクション（テーブル定義・カラム一覧など）ごとに 1 枚のカードを作り、
        その中を before / after の 2 ペインに分けます。左右のペインは
        横スクロールと縦スクロールが同期します（JavaScript を埋め込み）。

        JavaScript が動かない環境でも、各ペインは独立にスクロールできるため
        閲覧そのものは成立します（同期しなくなるだけ）。

        見出し・凡例などの文言は日本語です。
    .PARAMETER Title
        文書の題名。<title> と先頭の見出しに使います。HTML としてエスケープしてから埋め込みます。
    .PARAMETER Sections
        @{ Label = 'テーブル定義'; Rows = <Get-DiffAlignment の戻り値>; Unverified = @('...') }
        の配列。Unverified が指定されたセクションは、差分の代わりにその内容を表示します。
        before か after の取得に失敗して比較できないセクションに使います。
        「差分なし」と見分けが付かない表示にしないためです。
    .OUTPUTS
        [string] HTML 文書全体。
    .EXAMPLE
        PS> $before = @(Get-Content -LiteralPath .\before.txt -Encoding UTF8)
        PS> $after = @(Get-Content -LiteralPath .\after.txt -Encoding UTF8)
        PS> $rows = Get-DiffAlignment -BeforeLines $before -AfterLines $after
        PS> $html = ConvertTo-DiffHtml -Title 'settings' -Sections @(@{ Label = 'アプリ設定'; Rows = $rows })
        PS> [System.IO.File]::WriteAllText("$PWD\diff.html", $html, [System.Text.UTF8Encoding]::new($false))

        2 つのファイルの差分を、左右に並べた HTML として保存します。
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string]$Title,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [array]$Sections
    )

    $escapedTitle = ConvertTo-HtmlText -Text $Title
    $builder = [System.Text.StringBuilder]::new()

    [void]$builder.AppendLine('<!doctype html>')
    [void]$builder.AppendLine('<html lang="ja">')
    [void]$builder.AppendLine('<head>')
    [void]$builder.AppendLine('<meta charset="utf-8">')
    [void]$builder.AppendLine("<title>$escapedTitle</title>")
    [void]$builder.AppendLine('<style>')
    [void]$builder.AppendLine((Get-DiffHtmlStyle))
    [void]$builder.AppendLine('</style>')
    [void]$builder.AppendLine('</head>')
    [void]$builder.AppendLine('<body>')
    [void]$builder.AppendLine('<div class="wrap">')
    [void]$builder.AppendLine("<h1>$escapedTitle</h1>")

    foreach ($section in $Sections) {
        $label = ConvertTo-HtmlText -Text ([string]$section.Label)
        [void]$builder.AppendLine('<div class="card">')
        [void]$builder.AppendLine("  <div class=""card-head"">$label</div>")

        if ($section.ContainsKey('Unverified') -and $null -ne $section.Unverified) {
            # 取得に失敗した側があるセクション。差分は計算できないので理由を出す。
            # 「差分なし」と見分けが付かない表示にしてはならない
            [void]$builder.AppendLine('  <div class="unverified">')
            foreach ($line in @($section.Unverified)) {
                [void]$builder.AppendLine('    <div>' + (ConvertTo-HtmlText -Text $line) + '</div>')
            }
            [void]$builder.AppendLine('  </div>')
            [void]$builder.AppendLine('</div>')
            continue
        }

        $rows = @($section.Rows)
        if (@($rows | Where-Object -FilterScript { $_.Kind -cne 'Same' }).Count -eq 0) {
            [void]$builder.AppendLine('  <div class="nodiff">(差分なし)</div>')
            [void]$builder.AppendLine('</div>')
            continue
        }

        [void]$builder.AppendLine('  <div class="side"><div>before（適用前）</div><div>after（適用後）</div></div>')
        [void]$builder.AppendLine('  <div class="panes">')
        [void]$builder.AppendLine((Get-DiffHtmlPane -Rows $rows -Side 'left'))
        [void]$builder.AppendLine((Get-DiffHtmlPane -Rows $rows -Side 'right'))
        [void]$builder.AppendLine('  </div>')
        [void]$builder.AppendLine((Get-DiffHtmlLegend))
        [void]$builder.AppendLine('</div>')
    }

    [void]$builder.AppendLine('</div>')
    [void]$builder.AppendLine('<script>')
    [void]$builder.AppendLine((Get-DiffHtmlScript))
    [void]$builder.AppendLine('</script>')
    [void]$builder.AppendLine('</body>')
    [void]$builder.AppendLine('</html>')

    return $builder.ToString()
}
