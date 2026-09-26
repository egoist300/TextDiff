#Requires -Version 5.1

function Split-DiffToken {
    <#
    .SYNOPSIS
        1 行を、行内比較の単位（トークン）へ分割する。
    .DESCRIPTION
        英数字とアンダースコアの連続を 1 つのトークンとし、それ以外の文字は
        1 文字ずつ独立したトークンにします。連結すると元の文字列に戻ります
        （欠落や変換をしないため、強調位置がずれません）。
    .PARAMETER Text
        分割する 1 行。空文字も受け取ります。
    .OUTPUTS
        [string[]] トークンの配列。Text が空文字なら空配列。
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Text
    )

    $tokens = [System.Collections.Generic.List[string]]::new()
    if ($Text.Length -eq 0) { return $tokens.ToArray() }

    $buffer = [System.Text.StringBuilder]::new()
    foreach ($ch in $Text.ToCharArray()) {
        # [A-Za-z0-9_] のみを「語」とする。Char.IsLetterOrDigit を使うと
        # 日本語も語に含まれてしまい、長い日本語の連なりが 1 トークンになって
        # 「どこが変わったか」を示せなくなる
        $isWord = ($ch -ge 'a' -and $ch -le 'z') -or ($ch -ge 'A' -and $ch -le 'Z') -or ($ch -ge '0' -and $ch -le '9') -or ($ch -ceq '_')
        if ($isWord) {
            [void]$buffer.Append($ch)
        }
        else {
            if ($buffer.Length -gt 0) { $tokens.Add($buffer.ToString()); [void]$buffer.Clear() }
            $tokens.Add([string]$ch)
        }
    }
    if ($buffer.Length -gt 0) { $tokens.Add($buffer.ToString()) }

    return $tokens.ToArray()
}
