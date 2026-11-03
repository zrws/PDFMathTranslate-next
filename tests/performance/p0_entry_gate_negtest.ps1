# Entry-gate negative tests (G04/G05/G15) + positive control (G14), v2.
# ASCII only, PS 5.1 safe. Lightweight stubs ONLY - no product code import.
#
# Gate-A review fixes (2026-09-30, round r2-integrated-20261003-01):
#   M2: G05 now runs WITHOUT PDF2ZH_GUARD_SHA256 so the recovery actually
#       reaches the STALE-PID handshake branch (a hash-first death would be
#       indistinguishable from G15).
#   M3: every child's stdout/stderr is captured to files and the gate's
#       rejection reason string is ASSERTED per case (exit-code-only verdicts
#       are rejected); output/error logs are kept in the run dir.
#   MINOR: the G04 read-only flag is always cleared in finally.
#   MINOR: the case matrix file is named matrix.csv (checker-compatible).
#
# Cases:
#   POS: healthy handshake with correct hash -> gate passes, target runs
#   G04: guard log read-only -> autoload cannot mark -> gate blocks
#        (reason asserted: no GUARD_ACTIVE / handshake missing)
#   G05: stale handshake from another PID (no autoload, no sha) -> rejected
#        (reason asserted: no GUARD_ACTIVE entry with PID)
#   G15a: sitecustomize absent from guard dir -> hash binding fails
#   G15b: sitecustomize present but corrupted -> hash mismatch
# Exit: 0 all cases pass; 1 any failure; 4 prerequisite missing.

param(
    [string]$RepoRoot = 'D:\paper\PDFMathTranslate-next',
    [string]$InstallRoot = 'D:\paper\pdf2zh-install-test',
    [string]$OutDir = ''
)

$ErrorActionPreference = 'Continue'
. (Join-Path $RepoRoot 'tests\performance\p0_env.ps1')

$guardDir = Join-Path $RepoRoot 'tests\performance\p0_guard'
$python = Get-ChildItem (Join-Path $InstallRoot 'uv-python') -Recurse -Filter python.exe |
    Select-Object -First 1 -ExpandProperty FullName
$wrapper = Join-Path $guardDir 'entry_wrapper.py'
$spPath = 'D:\paper\pdf2zh-install-test\uv-tools\pdf2zh-next\Lib\site-packages'
if (-not $python -or -not (Test-Path $wrapper)) { Write-Host '[FAIL] prerequisite missing'; exit 4 }

if (-not $OutDir) {
    $OutDir = Join-Path $RepoRoot ("docs\verification\native-desktop\r2-integrated-20261003-01\runs\entrygate-" +
        (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + $PID)
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$hashFiles = @('entry_gate.py','entry_wrapper.py','sitecustomize.py')
$hashes = [ordered]@{}
foreach ($f in $hashFiles) { $hashes[$f] = (Get-FileHash (Join-Path $guardDir $f) -Algorithm SHA256).Hash }
$hashes['p0_env.ps1'] = (Get-FileHash (Join-Path $RepoRoot 'tests\performance\p0_env.ps1') -Algorithm SHA256).Hash
$hashes['p0_entry_gate_negtest.ps1'] = (Get-FileHash $PSCommandPath -Algorithm SHA256).Hash   # self-hash (D8 minor)
$hashes | ConvertTo-Json | Set-Content (Join-Path $OutDir 'script-hashes.json') -Encoding UTF8

function New-ChildEnv([string]$guardLog, [string]$sentinel, [string]$sha, [string]$guardDirForChild, [string]$pyPath, [string]$outLog, [string]$errLog) {
    $pinfo = [System.Diagnostics.ProcessStartInfo]::new()
    $pinfo.FileName = "$env:ComSpec"
    $pinfo.Arguments = '/c ""' + $python + '" -u "' + $wrapper + '" > "' + $outLog + '" 2> "' + $errLog + '"'
    $pinfo.UseShellExecute = $false
    $pinfo.CreateNoWindow = $true
    # PYTHONPATH controls whether the working sitecustomize autoloads:
    # POS/G04 -> real guard dir (autoload ON); G05 -> site-packages only
    $pinfo.EnvironmentVariables['PYTHONPATH'] = $pyPath
    $pinfo.EnvironmentVariables['PDF2ZH_GUARD_LOG'] = $guardLog
    $pinfo.EnvironmentVariables['PDF2ZH_GUARD_DIR'] = $guardDirForChild
    $pinfo.EnvironmentVariables['PDF2ZH_RUN_ID'] = 'entrygate-' + [guid]::NewGuid().ToString('N').Substring(0,8)
    $pinfo.EnvironmentVariables['PDF2ZH_TARGET_SCRIPT'] = $sentinelPy
    $pinfo.EnvironmentVariables['SENTINEL_PATH'] = $sentinel
    if ($sha) { $pinfo.EnvironmentVariables['PDF2ZH_GUARD_SHA256'] = $sha }
    return $pinfo
}

$cases = New-Object System.Collections.Generic.List[string]
$script:fails = 0

# Sentinel target: the "app" for gate tests. Writes a marker file so the host
# can PROVE whether the gate allowed the target to run.
$sentinelPy = Join-Path $OutDir 'sentinel_target.py'
@'
import os, sys
p = os.environ.get("SENTINEL_PATH", "")
if p:
    with open(p, "w", encoding="utf-8") as f:
        f.write("TARGET_RAN pid=%d\n" % os.getpid())
sys.exit(0)
'@ | Set-Content -Path $sentinelPy -Encoding ASCII

# Produce a REAL healthy handshake by briefly starting a child that autoloads
# the working sitecustomize (GUARD_ACTIVE for that child's PID lands in log).
function New-HealthyHandshake([string]$guardLog, [string]$wsDir) {
    $genPy = Join-Path $wsDir 'gen_handshake.py'
    'print("ok")' | Set-Content $genPy -Encoding ASCII
    $saved = Set-ChildEnvBlock @('PDF2ZH_GUARD_LOG','PYTHONPATH')
    try {
        $pi0 = [System.Diagnostics.ProcessStartInfo]::new()
        $pi0.FileName = $python
        $pi0.Arguments = '-u "' + $genPy + '"'
        $pi0.UseShellExecute = $false; $pi0.CreateNoWindow = $true
        $pi0.EnvironmentVariables['PYTHONPATH'] = $guardDir
        $pi0.EnvironmentVariables['PDF2ZH_GUARD_LOG'] = $guardLog
        [void][System.Diagnostics.Process]::Start($pi0).WaitForExit(30000)
    } finally { Restore-ChildEnv $saved }
    return (Test-Path $guardLog) -and ((Get-Content $guardLog -Raw) -match 'GUARD_ACTIVE \d+')
}

function Run-Case([string]$id, [string]$expectExit, [string]$expectReason, [scriptblock]$action) {
    Write-Host ("=== {0} ===" -f $id)
    $res = & $action
    $verdict = if ("$($res.exit)" -eq "$expectExit") { 'PASS' } else { 'FAIL' }
    # M3: assert the gate's rejection/success REASON from the captured stderr
    $reasonOk = $true
    if ($expectReason) {
        if ("$($res.gateStderr)" -notmatch [regex]::Escape($expectReason)) { $reasonOk = $false }
    } elseif ($expectExit -eq '1') {
        $reasonOk = $false   # negative cases MUST carry an asserted reason
    }
    if (-not $reasonOk) { $verdict = 'FAIL' }
    if ($verdict -eq 'FAIL') { $script:fails++ }
    $cases.Add(("{0},{1},{2},{3},{4}" -f $id, $expectExit, $res.exit, $verdict, $expectReason)) | Out-Null
    Write-Host ("  exit={0} expected={1} sentinelRan={2} reasonOk={3} verdict={4} gateStderr={5}" -f
        $res.exit, $expectExit, $res.sentinelRan, $reasonOk, $verdict, ($res.gateStderr -replace "`r`n", ' | '))
}

# --- POS: healthy handshake + hash -> gate passes, target runs -----------------
Run-Case 'POS-healthy-handshake' '0' $null {
    $dir = Join-Path $OutDir 'pos-healthy'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $guardLog = Join-Path $dir 'guard.log'
    $sentinel = Join-Path $dir 'sentinel.txt'
    Remove-Item $guardLog, $sentinel -ErrorAction SilentlyContinue
    $sha = (Get-FileHash (Join-Path $guardDir 'sitecustomize.py') -Algorithm SHA256).Hash
    if (-not (New-HealthyHandshake $guardLog $dir)) {
        return @{ exit = 9; sentinelRan = $false; gateStderr = 'no GUARD_ACTIVE produced by healthy child' }
    }
    $pinfo = New-ChildEnv $guardLog $sentinel $sha $guardDir ($guardDir + ';' + $spPath) `
        (Join-Path $dir 'child.out.txt') (Join-Path $dir 'child.err.txt')
    $proc = [System.Diagnostics.Process]::Start($pinfo)
    [void]$proc.WaitForExit(30000)
    $exit = if ($proc.HasExited) { $proc.ExitCode } else { -1 }
    $sentinelRan = (Test-Path $sentinel) -and ((Get-Content $sentinel -Raw) -match 'TARGET_RAN')
    $appEntered = ((Get-Content $guardLog -Raw) -match 'APP_ENTERED')
    @{ exit = $exit; sentinelRan = $sentinelRan
       gateStderr = if ($appEntered) { 'APP_ENTERED present' } else { 'APP_ENTERED missing' } }
}

# --- G04: log read-only -> guard cannot write -> gate blocks -------------------
Run-Case 'G04-guard-log-unwritable' '1' 'no GUARD_ACTIVE entry with PID' {
    $dir = Join-Path $OutDir 'g04'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $guardLog = Join-Path $dir 'guard.log'
    $sentinel = Join-Path $dir 'sentinel.txt'
    $shaderFile = Join-Path $dir 'child.err.txt'
    Remove-Item $guardLog, $sentinel, $shaderFile -ErrorAction SilentlyContinue
    $sha = (Get-FileHash (Join-Path $guardDir 'sitecustomize.py') -Algorithm SHA256).Hash
    if (-not (New-HealthyHandshake $guardLog $dir)) {
        return @{ exit = -2; sentinelRan = $false; gateStderr = 'could not obtain healthy handshake for G04 setup' }
    }
    $item = Get-Item $guardLog
    $prevReadOnly = $item.IsReadOnly
    try {
        $item.IsReadOnly = $true
        $pinfo = New-ChildEnv $guardLog $sentinel $sha $guardDir ($guardDir + ';' + $spPath) `
            (Join-Path $dir 'child.out.txt') $shaderFile
        $proc = [System.Diagnostics.Process]::Start($pinfo)
        [void]$proc.WaitForExit(30000)
        $exit = if ($proc.HasExited) { $proc.ExitCode } else { -1 }
    } finally {
        $item.IsReadOnly = $prevReadOnly
    }
    $sentinelRan = Test-Path $sentinel
    $logText = Get-Content $guardLog -Raw -ErrorAction SilentlyContinue
    if (-not ($exit -eq 1) -or $sentinelRan -or ($logText -match 'APP_ENTERED')) {
        return @{ exit = $exit; sentinelRan = $sentinelRan; gateStderr = 'gate did NOT block an unwritable log' }
    }
    @{ exit = $exit; sentinelRan = $sentinelRan
       gateStderr = (Get-Content $shaderFile -Raw -ErrorAction SilentlyContinue) }
}

# --- G05: stale handshake from ANOTHER PID (no autoload, no sha) ---------------
Run-Case 'G05-stale-handshake' '1' 'no GUARD_ACTIVE entry with PID' {
    $dir = Join-Path $OutDir 'g05'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $guardLog = Join-Path $dir 'guard.log'
    $sentinel = Join-Path $dir 'sentinel.txt'
    $shaderFile = Join-Path $dir 'child.err.txt'
    Remove-Item $guardLog, $sentinel, $shaderFile -ErrorAction SilentlyContinue
    $sha = (Get-FileHash (Join-Path $guardDir 'sitecustomize.py') -Algorithm SHA256).Hash
    # pre-write a stale GUARD_ACTIVE owned by a PID not owned by the child;
    # NO SHA (M2) and NO autoload so the PID handshake branch is reached
    $stalePid = (Get-Random -Minimum 4000000 -Maximum 4194000)
    Set-Content -Path $guardLog -Value ("GUARD_ACTIVE {0} stale" -f $stalePid) -Encoding ASCII
    $pinfo = New-ChildEnv $guardLog $sentinel $null $guardDir ($spPath) `
        (Join-Path $dir 'child.out.txt') $shaderFile
    $proc = [System.Diagnostics.Process]::Start($pinfo)
    [void]$proc.WaitForExit(30000)
    $exit = if ($proc.HasExited) { $proc.ExitCode } else { -1 }
    $sentinelRan = Test-Path $sentinel
    $logText = Get-Content $guardLog -Raw -ErrorAction SilentlyContinue
    if ($sentinelRan -or ($logText -match 'APP_ENTERED')) {
        return @{ exit = $exit; sentinelRan = $sentinelRan; gateStderr = 'stale handshake was NOT rejected' }
    }
    @{ exit = $exit; sentinelRan = $sentinelRan
       gateStderr = (Get-Content $shaderFile -Raw -ErrorAction SilentlyContinue) }
}

# --- G15a: sitecustomize missing from the (copied) guard dir -------------------
Run-Case 'G15a-sitecustomize-missing' '1' 'sitecustomize module not loaded' {
    $dir = Join-Path $OutDir 'g15a'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $brokenGuardDir = Join-Path $dir 'guard_dir'
    New-Item -ItemType Directory -Force -Path $brokenGuardDir | Out-Null
    Copy-Item (Join-Path $guardDir 'entry_wrapper.py') $brokenGuardDir
    Copy-Item (Join-Path $guardDir 'entry_gate.py') $brokenGuardDir
    $guardLog = Join-Path $dir 'guard.log'
    $sentinel = Join-Path $dir 'sentinel.txt'
    $shaderFile = Join-Path $dir 'child.err.txt'
    Remove-Item $guardLog, $sentinel, $shaderFile -ErrorAction SilentlyContinue
    Set-Content -Path $guardLog -Value 'GUARD_ACTIVE 123456 stale' -Encoding ASCII
    $sha = (Get-FileHash (Join-Path $guardDir 'sitecustomize.py') -Algorithm SHA256).Hash
    $pinfo = New-ChildEnv $guardLog $sentinel $sha $brokenGuardDir ($brokenGuardDir + ';' + $spPath) `
        (Join-Path $dir 'child.out.txt') $shaderFile
    $proc = [System.Diagnostics.Process]::Start($pinfo)
    [void]$proc.WaitForExit(30000)
    $exit = if ($proc.HasExited) { $proc.ExitCode } else { -1 }
    $sentinelRan = Test-Path $sentinel
    @{ exit = $exit; sentinelRan = $sentinelRan
       gateStderr = (Get-Content $shaderFile -Raw -ErrorAction SilentlyContinue) }
}

# --- G15b: sitecustomize present but corrupted (= wrong hash) ------------------
Run-Case 'G15b-sitecustomize-hash-mismatch' '1' 'guard hash mismatch' {
    $dir = Join-Path $OutDir 'g15b'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $brokenGuardDir = Join-Path $dir 'guard_dir'
    New-Item -ItemType Directory -Force -Path $brokenGuardDir | Out-Null
    Copy-Item (Join-Path $guardDir 'entry_wrapper.py') $brokenGuardDir
    Copy-Item (Join-Path $guardDir 'entry_gate.py') $brokenGuardDir
    '# corrupted sitecustomize pass' | Set-Content (Join-Path $brokenGuardDir 'sitecustomize.py') -Encoding ASCII
    $guardLog = Join-Path $dir 'guard.log'
    $sentinel = Join-Path $dir 'sentinel.txt'
    $shaderFile = Join-Path $dir 'child.err.txt'
    Remove-Item $guardLog, $sentinel, $shaderFile -ErrorAction SilentlyContinue
    Set-Content -Path $guardLog -Value 'GUARD_ACTIVE 123456 stale' -Encoding ASCII
    $sha = (Get-FileHash (Join-Path $guardDir 'sitecustomize.py') -Algorithm SHA256).Hash
    $pinfo = New-ChildEnv $guardLog $sentinel $sha $brokenGuardDir ($brokenGuardDir + ';' + $spPath) `
        (Join-Path $dir 'child.out.txt') $shaderFile
    $proc = [System.Diagnostics.Process]::Start($pinfo)
    [void]$proc.WaitForExit(30000)
    $exit = if ($proc.HasExited) { $proc.ExitCode } else { -1 }
    $sentinelRan = Test-Path $sentinel
    @{ exit = $exit; sentinelRan = $sentinelRan
       gateStderr = (Get-Content $shaderFile -Raw -ErrorAction SilentlyContinue) }
}

'case,expectedExit,actualExit,verdict,expectedReason' | Set-Content (Join-Path $OutDir 'matrix.csv') -Encoding ASCII
$cases | ForEach-Object { Add-Content -Path (Join-Path $OutDir 'matrix.csv') $_ -Encoding ASCII }
Get-Content (Join-Path $OutDir 'matrix.csv')
if ($script:fails -gt 0) { Write-Host ("[FAIL] entry-gate negatives: {0} failed" -f $script:fails); exit 1 }
Write-Host '[PASS] entry-gate negative tests pass'
exit 0

