#Requires -Version 5.1

function Split-DiffToken {
    <#
    .SYNOPSIS
        1 行を、行内比較の単位（トークン）へ分割する。
    .DESCRIPTION
        英数字とアンダースコアの連続を 1 つのトークンとし、それ以外の文字は
        1 文字ずつ独立したトークンにします。トークンを連結すると元の文字列に一致します。
    .PARAMETER Text
        分割する 1 行。空文字も受け取ります。
    .OUTPUTS
        [string[]] トークンの配列。Text が空文字なら空配列。
    .EXAMPLE
        Split-DiffToken -Text 'varying(100),'
        # 'varying' / '(' / '100' / ')' / ','
    .EXAMPLE
        Split-DiffToken -Text '2026-08-17'
        # '2026' / '-' / '08' / '-' / '17'
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Text
    )

    if ($Text.Length -eq 0) { return [string[]]@() }

    # [A-Za-z0-9_] だけを語の構成文字とする。Char.IsLetterOrDigit では日本語も語に含まれ、
    # 長い日本語の文字列が 1 トークンになって、変更箇所を示せなくなる。
    # 記号を 1 文字ずつのトークンにするのは、括弧やハイフンをまたぐ変更を、その部分だけ示すため。
    # PowerShell のループで 1 文字ずつ判定する方法も、正規表現の一致を for で 1 つずつ取り出す方法も遅いため、
    # 一致の Value をメンバーの列挙でまとめて取り出す。
    # 1000 行で、1 文字ずつ判定する方法の約 300 ミリ秒に対して約 160 ミリ秒だった（Windows PowerShell 5.1 での実測）。
    # Regex.Split の結果から -cne '' で空文字を除く方法は使わない。-cne はカルチャーに依存する比較で、
    # ソフトハイフンなどの無視される文字を空文字と等しいと判定し、トークンごと除いてしまう。
    # [\s\S] は UTF-16 のコード単位 1 つに一致し、改行も含めて取りこぼさない。
    return [string[]]([regex]::Matches($Text, '[A-Za-z0-9_]+|[\s\S]').Value)
}
