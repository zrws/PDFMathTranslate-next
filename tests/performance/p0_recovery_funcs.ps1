# Shared recovery identity functions (R4, ASCII only, PS 5.1 safe).
# SINGLE SOURCE used by p0_recovery_negtest.ps1 and (conceptually identical to)
# the inline recovery logic in p0_probe_perprocess.ps1 / p0_probe_attribution.ps1.
# States: gone / still_alive_same_identity / pid_reused / query_failed.
# query_failed ALWAYS fails acceptance (never silently 'gone').

function Get-RecoveryIdentity([int]$ProcessId) {
    $cim = Get-CimInstance Win32_Process -Filter ("ProcessId = " + $ProcessId) -ErrorAction SilentlyContinue
    if ($cim) { return [pscustomobject]@{ pid = $cim.ProcessId; created = $cim.CreationDate; name = $cim.Name } }
    return $null
}

function Get-RecoveryReport {
    param(
        [Parameter(Mandatory)]$Identities,
        [scriptblock]$CimLookup = $null,   # test-only seam: override CIM lookup
        [scriptblock]$ProcLookup = $null   # test-only seam: override Get-Process
    )
    # R4-fix: collect rows as an ARRAY - a Generic List stored in a hashtable
    # makes .rows / Item['rows'] access throw "Argument types do not match"
    # in this PS environment (same family as the OD assignment quirk)
    $rows = @()
    $allGone = $true
    foreach ($idn in $Identities) {
        $status = 'gone'
        $gp = $null
        if ($ProcLookup) { $gp = & $ProcLookup $idn.pid }
        else {
            try { $gp = Get-Process -Id $idn.pid -ErrorAction Stop } catch { $gp = $null }
        }
        if ($gp) {
            $cim = $null
            $queryFailed = $false
            if ($CimLookup) {
                try { $cim = & $CimLookup $idn.pid } catch { $queryFailed = $true }
            } else {
                try {
                    $cim = Get-CimInstance Win32_Process -Filter ("ProcessId = " + $idn.pid) -ErrorAction Stop
                } catch { $queryFailed = $true }
            }
            if ($queryFailed) {
                $status = 'query_failed'; $allGone = $false
            } elseif ($cim -and $cim.CreationDate -eq $idn.created) {
                $status = 'still_alive_same_identity'; $allGone = $false
            } else {
                $status = 'pid_reused'
            }
        }
        $rows += [pscustomobject]@{ pid = $idn.pid; created = $idn.created; name = $idn.name; post_status = $status }
    }
    return @{ rows = [object[]]$rows; all_gone = $allGone }
}
