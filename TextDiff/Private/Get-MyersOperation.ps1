#Requires -Version 5.1

function Get-MyersOperation {
    <#
    .SYNOPSIS
        Myers 法で、変更前から変更後への最短の編集操作（Same / Deleted / Added）を算出する。
    .DESCRIPTION
        Changed（変更）の判定は行いません。削除行と追加行の対応付けは Get-DiffAlignment が行います。
    .PARAMETER Left
        変更前の行 ID の配列（ConvertTo-LineId の Left）。空の配列も受け取ります。
    .PARAMETER Right
        変更後の行 ID の配列（ConvertTo-LineId の Right）。空の配列も受け取ります。
    .OUTPUTS
        [System.Collections.Generic.List[hashtable]]
        @{ Kind = 'Same'|'Deleted'|'Added'; LeftIndex = 変更前の添字 or $null; RightIndex = 変更後の添字 or $null }
        の List。変更前と変更後のすべての要素を、先頭から順に 1 回ずつ含みます。
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.List[hashtable]])]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [int[]]$Left,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [int[]]$Right
    )

    $leftLength = $Left.Length
    $rightLength = $Right.Length
    $ops = [System.Collections.Generic.List[hashtable]]::new()

    # 片側が空なら、Myers 法を実行する必要はない。
    if ($leftLength -eq 0 -and $rightLength -eq 0) { return $ops }
    if ($leftLength -eq 0) {
        for ($rightIndex = 0; $rightIndex -lt $rightLength; $rightIndex++) {
            $ops.Add(@{ Kind = 'Added'; LeftIndex = $null; RightIndex = $rightIndex })
        }
        return $ops
    }
    if ($rightLength -eq 0) {
        for ($leftIndex = 0; $leftIndex -lt $leftLength; $leftIndex++) {
            $ops.Add(@{ Kind = 'Deleted'; LeftIndex = $leftIndex; RightIndex = $null })
        }
        return $ops
    }

    # 変数名と論文（Myers, "An O(ND) Difference Algorithm and Its Variations"）の記号の対応:
    #   $leftLength = N / $rightLength = M / $editCount = D / $diagonal = k /
    #   $leftPos = x / $rightPos = y / $furthest = V（対角線ごとの最も遠い x）
    # 添字の中の算術は必ず括弧で囲む。$table[$row + 1, $column] は $table[$row + (1, $column)] と解釈され、
    # 配列の連結になって失敗する。
    $maxEditCount = $leftLength + $rightLength
    $size = 2 * $maxEditCount + 2
    $offset = $maxEditCount
    $furthest = New-Object -TypeName 'int[]' -ArgumentList $size
    # 各段の V を保存する。保存しないと経路を復元できない。
    # PowerShell のループで複製すると D に比例して遅くなるため、[Array]::Copy で複製する。
    $trace = [System.Collections.Generic.List[int[]]]::new()

    $shortestEditCount = -1
    for ($editCount = 0; $editCount -le $maxEditCount; $editCount++) {
        $furthestCopy = New-Object -TypeName 'int[]' -ArgumentList $size
        [Array]::Copy($furthest, $furthestCopy, $size)
        $trace.Add($furthestCopy)

        for ($diagonal = -$editCount; $diagonal -le $editCount; $diagonal += 2) {
            $slot = $offset + $diagonal
            if ($diagonal -ceq -$editCount -or ($diagonal -cne $editCount -and $furthest[($slot - 1)] -lt $furthest[($slot + 1)])) {
                $leftPos = $furthest[($slot + 1)]
            }
            else {
                $leftPos = $furthest[($slot - 1)] + 1
            }
            $rightPos = $leftPos - $diagonal
            # 一致が続く間、対角線方向に進む。
            while ($leftPos -lt $leftLength -and $rightPos -lt $rightLength -and $Left[$leftPos] -ceq $Right[$rightPos]) {
                $leftPos++
                $rightPos++
            }
            $furthest[$slot] = $leftPos
            if ($leftPos -ge $leftLength -and $rightPos -ge $rightLength) { $shortestEditCount = $editCount; break }
        }
        if ($shortestEditCount -ge 0) { break }
    }

    # --- 経路の復元（末尾から先頭へ）---
    $leftPos = $leftLength
    $rightPos = $rightLength
    for ($editCount = $shortestEditCount; $editCount -gt 0; $editCount--) {
        $previousFurthest = $trace[$editCount]
        $diagonal = $leftPos - $rightPos
        $slot = $offset + $diagonal
        if ($diagonal -ceq -$editCount -or ($diagonal -cne $editCount -and $previousFurthest[($slot - 1)] -lt $previousFurthest[($slot + 1)])) {
            $previousDiagonal = $diagonal + 1
        }
        else {
            $previousDiagonal = $diagonal - 1
        }
        $previousLeftPos = $previousFurthest[($offset + $previousDiagonal)]
        $previousRightPos = $previousLeftPos - $previousDiagonal

        while ($leftPos -gt $previousLeftPos -and $rightPos -gt $previousRightPos) {
            $ops.Add(@{ Kind = 'Same'; LeftIndex = ($leftPos - 1); RightIndex = ($rightPos - 1) })
            $leftPos--
            $rightPos--
        }
        if ($leftPos -gt $previousLeftPos) { $ops.Add(@{ Kind = 'Deleted'; LeftIndex = ($leftPos - 1); RightIndex = $null }) }
        else { $ops.Add(@{ Kind = 'Added'; LeftIndex = $null; RightIndex = ($rightPos - 1) }) }
        $leftPos = $previousLeftPos
        $rightPos = $previousRightPos
    }
    while ($leftPos -gt 0 -and $rightPos -gt 0) {
        $ops.Add(@{ Kind = 'Same'; LeftIndex = ($leftPos - 1); RightIndex = ($rightPos - 1) })
        $leftPos--
        $rightPos--
    }

    $ops.Reverse()
    return $ops
}
