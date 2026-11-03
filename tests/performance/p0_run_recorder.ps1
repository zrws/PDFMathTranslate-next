# Outer run recorder (R4, ASCII only, PS 5.1 safe).
# Launches an entry script as a child process and records the OBSERVED facts:
#   - actual Process.ExitCode (never the entry's self-reported planned exit)
#   - timeout / outer exception states
#   - full stdout/stderr (separate files)
#   - command + arguments + child PID + wall window
#   - runtime hashes of the entry + shared helpers
#   - binds the entry's own run dir (passed via -EntryOutDirArg, which must NOT
#     pre-exist: the recorder creates only its OWN directory, never the
#     entry's, so the entry's refuse-overwrite semantics stay intact)
# Exit: 0 entry exited (its code is recorded, NOT propagated); 3 timeout;
#       4 prerequisite missing; 5 recorder/evidence-write failure.

param(
    [Parameter(Mandatory)][string]$EntryScript,     # absolute path to the entry .ps1
    [string[]]$EntryArgs = @(),
    [string]$EntryOutDirArgName = 'OutDir',          # param name the entry uses for its run dir
    [Parameter(Mandatory)][string]$RecorderDir,     # THIS recorder's own dir (must be new)
    [string]$RepoRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent),
    [int]$TimeoutMinutes = 20
)

. (Join-Path $PSScriptRoot 'p0_paths.ps1')

$ErrorActionPreference = 'Continue'

if (Test-Path -LiteralPath $RecorderDir) {
    Write-Host ("[FAIL] recorder dir already exists and is non-empty: " + $RecorderDir)
    exit 2
}
New-Item -ItemType Directory -Force -Path $RecorderDir | Out-Null

if (-not (Test-Path $EntryScript)) {
    Write-Host ("[FAIL] entry script missing: " + $EntryScript)
    exit 4
}

# the entry's own run dir: a FRESH child path under the recorder dir
$entryRunDir = Join-Path $RecorderDir 'entry-run'
if (Test-Path $entryRunDir) {
    Write-Host ("[FAIL] entry run dir already exists (refuse overwrite): " + $entryRunDir)
    exit 2
}

$perfDir = Join-Path $RepoRoot 'tests\performance'
$depHashes = [ordered]@{}
foreach ($f in @('p0_baseline.ps1','p0_probe_perprocess.ps1','p0_probe_attribution.ps1',
                 'p0_asset_check.ps1','p0_paths.ps1','p0_runs.ps1','p0_env.ps1','p0_result.ps1','p0_run_recorder.ps1')) {
    $p = Join-Path $perfDir $f
    if (Test-Path $p) { $depHashes[$f] = (Get-FileHash $p -Algorithm SHA256).Hash }
}
foreach ($f in @('p0_guard\sitecustomize.py','p0_guard\entry_gate.py','p0_guard\entry_wrapper.py')) {
    $p = Join-Path $perfDir $f
    if (Test-Path $p) { $depHashes[$f] = (Get-FileHash $p -Algorithm SHA256).Hash }
}
$depHashes['entry'] = (Get-FileHash $EntryScript -Algorithm SHA256).Hash

$stdoutF = Join-Path $RecorderDir 'entry-stdout.txt'
$stderrF = Join-Path $RecorderDir 'entry-stderr.txt'
$windowStart = (Get-Date).ToString('o')

$argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $EntryScript) + $EntryArgs + @(('-' + $EntryOutDirArgName), $entryRunDir)

$timeoutHit = $false
$outerException = ''
$childPid = 0
$actualExit = $null
$windowEnd = ''
try {
    $p = Start-P0PowerShell -ArgumentList (($argList | ForEach-Object { ConvertTo-P0Argument $_ }) -join ' ') -PassThru -NoNewWindow `
        -RedirectStandardOutput $stdoutF -RedirectStandardError $stderrF
    $childPid = $p.Id
    $childIdentity = @{ pid = $p.Id; started_at = $p.StartTime.ToString('o'); executable = 'powershell.exe' }
    if (-not $p.WaitForExit($TimeoutMinutes * 60 * 1000)) {
        $timeoutHit = $true
        try {
            foreach ($cp in (Get-CimInstance Win32_Process -Filter ("ParentProcessId = " + $childPid))) {
                try { taskkill /PID $cp.ProcessId /T /F 2>$null | Out-Null } catch { }
            }
            try { $p.Kill() } catch { }
        } catch { }
        $actualExit = 'timeout'
        $windowEnd = (Get-Date).ToString('o')
    } else {
        $actualExit = $p.ExitCode
        $windowEnd = (Get-Date).ToString('o')
    }
} catch {
    $outerException = $_.Exception.Message
    $windowEnd = (Get-Date).ToString('o')
}

$observed = [ordered]@{
    recorder = 'p0_run_recorder.ps1'
    recorded_at = (Get-Date).ToString('o')
    entry = $EntryScript
    entry_args = ($EntryArgs -join ' ')
    command = ('powershell ' + ($argList -join ' '))
    child_pid = $childPid
    child_identity = $childIdentity
    argument_vector = $argList
    window = @{ started = $windowStart; ended = $windowEnd }
    timeout_minutes = $TimeoutMinutes
    timeout_hit = $timeoutHit
    outer_exception = $outerException
    actual_exit = $actualExit
    entry_run_dir = $entryRunDir
    entry_run_dir_exists = (Test-Path $entryRunDir)
    runtime_hashes = $depHashes
    stdout_path = $stdoutF
    stderr_path = $stderrF
    stdout_bytes = $(if (Test-Path $stdoutF) { (Get-Item $stdoutF).Length } else { -1 })
    stderr_bytes = $(if (Test-Path $stderrF) { (Get-Item $stderrF).Length } else { -1 })
}

$obsPath = Join-Path $RecorderDir 'observed.json'
try {
    $observed | ConvertTo-Json -Depth 5 | Set-Content -Path $obsPath -Encoding UTF8
} catch {
    Write-Host ("[FAIL] cannot write observed.json: " + $_.Exception.Message)
    exit 5
}
Write-Host ("[recorder] actual_exit={0} timeout={1} outer_exception={2}" -f $actualExit, $timeoutHit, ($outerException -ne ''))
Write-Host ("[recorder] observed: {0}" -f $obsPath)
if ($outerException) { exit 5 }
if ($timeoutHit) { exit 3 }
exit 0
