#Requires -Version 5.1

function ConvertTo-DiffHtml {
    <#
    .SYNOPSIS
        セクションごとの対応付けの結果を、1 つの HTML 文書に変換する。
    .DESCRIPTION
        セクション（比較する対象のファイルなど）ごとに 1 つのカードを作成し、変更前と変更後の
        2 つのペインを左右に並べます。左右のペインのスクロールは、埋め込んだ JavaScript で同期します。
        JavaScript が無効な環境でも、各ペインを個別にスクロールして閲覧できます。

        CSS と JavaScript は HTML に埋め込み、外部のファイルは読み込みません。
        見出しや凡例などの文言は日本語です。
    .PARAMETER Title
        文書の題名。<title> と先頭の見出しに使います。HTML としてエスケープしてから埋め込みます。
    .PARAMETER Sections
        @{ Label = 'アプリ設定'; Rows = <Get-DiffAlignment の戻り値>; Unverified = @('...') }の配列。
        Rows には Get-DiffAlignment の戻り値（TextDiff.DiffRow）だけを渡せます。
        Unverified を指定したセクションは、差分の代わりにその内容を表示します。
        変更前か変更後の取得に失敗し、比較できないセクションに使います。
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
        [Parameter(Mandatory)] [AllowEmptyCollection()] [hashtable[]]$Sections
    )

    # Rows の型は、HTML の生成前にすべてのセクションで検証する。
    # 差分の無いセクションは行を出力しないため、Get-DiffHtmlPane の引数の検証を経由しない。
    foreach ($section in $Sections) {
        if (-not $section.ContainsKey('Rows')) { continue }
        $foreignRows = @(@($section.Rows) | Where-Object -FilterScript { $_.PSObject.TypeNames -inotcontains 'TextDiff.DiffRow' })
        if ($foreignRows.Count -gt 0) {
            throw [System.ArgumentException]::new(("Sections の Rows には Get-DiffAlignment の戻り値を渡してください（セクション: {0}）" -f $section['Label']), 'Sections')
        }
    }

    $escapedTitle = ConvertTo-HtmlText -Text $Title
    $builder = [System.Text.StringBuilder]::new()

    [void]$builder.AppendLine('<!doctype html>')
    [void]$builder.AppendLine('<html lang="ja">')
    [void]$builder.AppendLine('<head>')
    [void]$builder.AppendLine('<meta charset="utf-8">')
    [void]$builder.AppendLine("<title>$escapedTitle</title>")
    # CSS と JavaScript を埋め込むのは、HTML ファイルを別のマシンにコピーしても表示が崩れないようにするため。
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
            # 取得に失敗した側があるセクションは、差分を計算できないため理由を表示する。
            # 「差分なし」と区別できない表示にしないため。
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

        # 変更前と変更後を左右に並べ、片側にしか無い行を斜線で示す。変更・削除・追加を位置で区別できる。
        # 削除行と追加行を上下に並べる表示では、どの行が対応するのか読み取れない。
        # HTML は保存して後から読むため、ConvertTo-DiffText と異なり行を省略しない。
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
