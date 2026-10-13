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

    # --- 1. 相手側に一致が無い要素を除外する ---
    # 相手側に一致が無い要素は必ず Deleted か Added になるため、先に除外して Myers 法の計算量を減らす。
    # 除外しても最短の編集は変わらず、残る要素は相手側にも必ず残るため、片側だけが空になることはない。
    $leftSet = [System.Collections.Generic.HashSet[int]]::new($Left)
    $rightSet = [System.Collections.Generic.HashSet[int]]::new($Right)
    $keptLeft = [System.Collections.Generic.List[int]]::new()
    $keptRight = [System.Collections.Generic.List[int]]::new()
    for ($leftIndex = 0; $leftIndex -lt $Left.Length; $leftIndex++) {
        if ($rightSet.Contains($Left[$leftIndex])) { $keptLeft.Add($leftIndex) }
    }
    for ($rightIndex = 0; $rightIndex -lt $Right.Length; $rightIndex++) {
        if ($leftSet.Contains($Right[$rightIndex])) { $keptRight.Add($rightIndex) }
    }
    $leftIds = New-Object -TypeName 'int[]' -ArgumentList $keptLeft.Count
    for ($keptIndex = 0; $keptIndex -lt $keptLeft.Count; $keptIndex++) { $leftIds[$keptIndex] = $Left[$keptLeft[$keptIndex]] }
    $rightIds = New-Object -TypeName 'int[]' -ArgumentList $keptRight.Count
    for ($keptIndex = 0; $keptIndex -lt $keptRight.Count; $keptIndex++) { $rightIds[$keptIndex] = $Right[$keptRight[$keptIndex]] }

    # --- 2. 残った要素を Myers 法で比較する ---
    # 添字は残った要素の中での位置。両方とも空なら、手数 0 で終了する。
    $leftLength = $leftIds.Length
    $rightLength = $rightIds.Length
    $keptOps = [System.Collections.Generic.List[hashtable]]::new()

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
            while ($leftPos -lt $leftLength -and $rightPos -lt $rightLength -and $leftIds[$leftPos] -ceq $rightIds[$rightPos]) {
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
            $keptOps.Add(@{ Kind = 'Same'; LeftIndex = ($leftPos - 1); RightIndex = ($rightPos - 1) })
            $leftPos--
            $rightPos--
        }
        if ($leftPos -gt $previousLeftPos) { $keptOps.Add(@{ Kind = 'Deleted'; LeftIndex = ($leftPos - 1); RightIndex = $null }) }
        else { $keptOps.Add(@{ Kind = 'Added'; LeftIndex = $null; RightIndex = ($rightPos - 1) }) }
        $leftPos = $previousLeftPos
        $rightPos = $previousRightPos
    }
    while ($leftPos -gt 0 -and $rightPos -gt 0) {
        $keptOps.Add(@{ Kind = 'Same'; LeftIndex = ($leftPos - 1); RightIndex = ($rightPos - 1) })
        $leftPos--
        $rightPos--
    }

    $keptOps.Reverse()

    # --- 3. 除外した要素を、元の位置に Deleted と Added として戻す ---
    # 残った要素の操作を元の添字に変換し、その手前にある除外した要素を先に出力する。
    $ops = [System.Collections.Generic.List[hashtable]]::new()
    $leftNext = 0
    $rightNext = 0
    foreach ($keptOp in $keptOps) {
        if ($null -ne $keptOp.LeftIndex) {
            $leftTarget = $keptLeft[$keptOp.LeftIndex]
            while ($leftNext -lt $leftTarget) { $ops.Add(@{ Kind = 'Deleted'; LeftIndex = $leftNext; RightIndex = $null }); $leftNext++ }
        }
        if ($null -ne $keptOp.RightIndex) {
            $rightTarget = $keptRight[$keptOp.RightIndex]
            while ($rightNext -lt $rightTarget) { $ops.Add(@{ Kind = 'Added'; LeftIndex = $null; RightIndex = $rightNext }); $rightNext++ }
        }
        switch -CaseSensitive ($keptOp.Kind) {
            'Same' { $ops.Add(@{ Kind = 'Same'; LeftIndex = $leftNext; RightIndex = $rightNext }); $leftNext++; $rightNext++ }
            'Deleted' { $ops.Add(@{ Kind = 'Deleted'; LeftIndex = $leftNext; RightIndex = $null }); $leftNext++ }
            'Added' { $ops.Add(@{ Kind = 'Added'; LeftIndex = $null; RightIndex = $rightNext }); $rightNext++ }
        }
    }
    while ($leftNext -lt $Left.Length) { $ops.Add(@{ Kind = 'Deleted'; LeftIndex = $leftNext; RightIndex = $null }); $leftNext++ }
    while ($rightNext -lt $Right.Length) { $ops.Add(@{ Kind = 'Added'; LeftIndex = $null; RightIndex = $rightNext }); $rightNext++ }

    return $ops
}
