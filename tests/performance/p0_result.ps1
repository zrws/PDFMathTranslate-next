# Shared structured result writer (ASCII only, PS 5.1 safe)
# C1/T3: every entry produces a result.json with the same schema.
# Usage:
#   . p0_result.ps1
#   $r = New-RunResult -RunId 'my-run' -Entry 'p0_baseline'
#   $r.samples = 12; $r.guardActive = $true
#   Write-RunResult $r -Path $resultPath

function New-RunResult {
    param(
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$Entry
    )
    return [ordered]@{
        run_id = $RunId
        entry = $Entry
        started_at = (Get-Date).ToString('o')
        ended_at = $null
        input_params = ''
        script_hashes = @{}
        verdict = 'UNKNOWN'        # PASS | FAIL | SKIP | NOT_RUN | UNKNOWN
        exit_code = $null           # actual outer exit code
        expected_exit = $null
        failure_stage = ''          # which phase failed
        reason_code = ''             # stable machine-readable reason
        reason_detail = ''
        samples = 0                  # number of valid data points
        expected_samples = 0
        guard_active = $null         # true/false/null
        guard_blocked_count = 0
        fallback_hits = 0
        owned_processes = @()        # [{pid, created, name}]
        processes_recovered = $null  # true/false
        port_released = $null        # true/false
        evidence_path = ''
        notes = ''
    }
}

function Write-RunResult {
    param($Result, [string]$Path)
    $Result['ended_at'] = (Get-Date).ToString('o')
    $Result | ConvertTo-Json -Depth 5 | Set-Content $Path -Encoding UTF8
}

function Add-OwnedProcess {
    param($Result, [int]$Pid, [string]$Name, [string]$Created)
    $Result['owned_processes'] += @(@{ pid = $Pid; name = $Name; created = $Created })
}
