#Requires -Version 5.1

function ConvertTo-DiffTextLine {
    <#
    .SYNOPSIS
        ConvertTo-DiffText が返す 1 行（TextDiff.TextLine）を作成する。
    .DESCRIPTION
        Text を渡すと、行全体を 1 つの共通部分の断片にします。Segments を渡すと、その断片をそのまま使用します。
    .PARAMETER Gutter
        行番号とマーカーの見出し。
    .PARAMETER Role
        'Removed' / 'Added' / 'Context' / 'Omitted' のいずれか。
    .PARAMETER Text
        行全体を 1 つの共通部分の断片にする場合の本文。空行も受け取ります。
    .PARAMETER Segments
        行内の変更箇所で分割した断片（TextDiff.Segment の配列）。省略行では渡しません。
    .PARAMETER OmittedCount
        省略した行数。Omitted 以外の行では 0。
    .OUTPUTS
        TextDiff.TextLine。[PSCustomObject]@{ Gutter; Role; Segments; OmittedCount }
    #>
    [CmdletBinding(DefaultParameterSetName = 'Segments')]
    [OutputType('TextDiff.TextLine')]
    param(
        [Parameter(Mandatory)] [string]$Gutter,
        [Parameter(Mandatory)] [ValidateSet('Removed', 'Added', 'Context', 'Omitted', IgnoreCase = $false)] [string]$Role,
        [Parameter(Mandatory, ParameterSetName = 'Text')] [AllowEmptyString()] [string]$Text,
        [Parameter(ParameterSetName = 'Segments')] [AllowEmptyCollection()] [psobject[]]$Segments = @(),
        [int]$OmittedCount = 0
    )

    # 行はこの関数だけで作成する。どの行にも同じ項目を持たせ、Format-Table の列を揃えるため。
    # 文字列ではなく断片の配列で返すのは、呼び出し側が変更箇所だけ色を変更できるようにするため。
    $lineSegments = if ($PSCmdlet.ParameterSetName -ceq 'Text') {
        [PSCustomObject]@{ PSTypeName = 'TextDiff.Segment'; Text = $Text; Changed = $false }
    }
    else {
        $Segments
    }
    return [PSCustomObject]@{
        PSTypeName   = 'TextDiff.TextLine'
        Gutter       = $Gutter
        Role         = $Role
        Segments     = @($lineSegments)
        OmittedCount = $OmittedCount
    }
}
