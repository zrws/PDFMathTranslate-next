# R4 recovery stub tests (ASCII only, PS 5.1 safe).
# Controlled stubs only - no user processes touched, no fault injection into
# system components. Proves the recovery VERDICT semantics:
#   1. process ALIVE but port closed     -> recovery acceptance must FAIL
#      (port release must never substitute for process death)
#   2. identity QUERY FAILURE             -> status query_failed, acceptance FAIL
#      (simulated by feeding a nonexistent PID whose Get-Process succeeds?
#       no - simulated via a stub identity list whose CIM lookup fails
#       because the PID does not exist but we FORCE the alive path with a
#       test-owned python stub whose identity we then corrupt)
#   3. PID IDENTITY MISMATCH (pid_reused) -> recorded as pid_reused, NOT gone,
#      and a still-alive same-identity stub FAILS acceptance
# Implementation: uses the SAME recovery functions the real entries use by
# dot-sourcing a shared recovery module (p0_recovery_funcs.ps1, extracted from
# the entries' inline logic so the entries and the stubs test ONE source).
# Exit: 0 all stubs behave as specified; 1 any mismatch.

param(
    [string]$RepoRoot = 'D:\paper\PDFMathTranslate-next',
    [string]$InstallRoot = 'D:\paper\pdf2zh-install-test',
    [string]$OutDir = ''
)

$ErrorActionPreference = 'Continue'
. (Join-Path $RepoRoot 'tests\performance\p0_recovery_funcs.ps1')

if (-not $OutDir) {
    $OutDir = Join-Path $RepoRoot ("docs\verification\native-desktop\r2-integrated-20261003-01\runs\recovery-stubs-" +
        (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + $PID)
}
if ((Test-Path $OutDir) -and (Get-ChildItem $OutDir -ErrorAction SilentlyContinue)) {
    Write-Host ("[FAIL] OutDir exists and non-empty (refuse overwrite): " + $OutDir); exit 2
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

@{
    'p0_recovery_funcs.ps1' = (Get-FileHash (Join-Path $RepoRoot 'tests\performance\p0_recovery_funcs.ps1') -Algorithm SHA256).Hash
    'p0_recovery_negtest.ps1' = (Get-FileHash $PSCommandPath -Algorithm SHA256).Hash
} | ConvertTo-Json | Set-Content (Join-Path $OutDir 'script-hashes.json') -Encoding UTF8

$python = Get-ChildItem (Join-Path $InstallRoot 'uv-python') -Recurse -Filter python.exe |
    Select-Object -First 1 -ExpandProperty FullName

$script:fails = 0
$rows = New-Object System.Collections.Generic.List[string]
function Check([string]$name, [bool]$ok, [string]$detail) {
    if ($ok) { Write-Host "[PASS] $name" } else { Write-Host ("[FAIL] {0} : {1}" -f $name, $detail); $script:fails++ }
    $rows.Add(("{0},{1}" -f $name, $(if ($ok) { 'PASS' } else { 'FAIL' })))
}

function New-StubPython([int]$seconds, [string]$tag) {
    # R4-fix: a stub .py file avoids -c quoting (Start-Process strips inner
    # quotes -> SyntaxError -> instant exit -> wrongly judged 'gone')
    $stubPy = Join-Path $OutDir ("stub-" + $tag + ".py")
    "import time, sys`nprint('STUB ' + sys.argv[1], flush=True)`ntime.sleep($seconds)" |
        Set-Content -Path $stubPy -Encoding ASCII
    $log = Join-Path $OutDir ("stub-" + $tag + ".txt")
    $p = Start-Process -FilePath $python -ArgumentList ('"' + $stubPy + '"', $tag) -PassThru -NoNewWindow -RedirectStandardOutput $log
    Start-Sleep -Milliseconds 500   # let the child print its tag before identity capture
    return $p
}

# --- stub 1: alive with port closed -------------------------------------------
$stub1 = New-StubPython 25 'alive-nolisten'
if (-not $stub1) { Write-Host '[FAIL] stub1 failed to launch'; $rows.Add('stub1-launch,FAIL') | Out-Null; $script:fails++ }
else {
    $ident1 = @(Get-RecoveryIdentity $stub1.Id)
    $rep1 = Get-RecoveryReport $ident1
    Check 'stub1: alive same-identity -> NOT all_gone (acceptance would FAIL)' (-not $rep1.all_gone) 'alive process was judged gone'
    Check 'stub1: status = still_alive_same_identity' (@($rep1.rows | Where-Object { $_.post_status -eq 'still_alive_same_identity' }).Count -eq 1) ((@($rep1.rows) | ForEach-Object { $_.post_status }) -join ',')
    # the port was NEVER open by this stub -> port_released would be true while
    # the process is alive: prove port observation alone would mislead
    $portListening = $false
    try { $portListening = [bool](Get-NetTCPConnection -OwningProcess $stub1.Id -State Listen -ErrorAction Stop) } catch { $portListening = $false }
    Check 'stub1: port closed while process alive (port alone would mislead)' (-not $portListening) 'stub unexpectedly listening'
    try { taskkill /PID $stub1.Id /T /F 2>$null | Out-Null } catch { }
}

# --- stub 2: identity mismatch (pid_reused) -------------------------------------
# create a real process, kill it; then create another that gets a different
# pid; feed the LIVE pid with a WRONG created time -> verdict must be pid_reused
$stub2 = New-StubPython 20 'mismatch-a'
if ($stub2) {
    try { taskkill /PID $stub2.Id /T /F 2>$null | Out-Null } catch { }
    Start-Sleep -Milliseconds 500
}
$stub3 = New-StubPython 20 'mismatch-b'
if (-not $stub3) { Write-Host '[FAIL] stub3 failed to launch'; $rows.Add('stub3-launch,FAIL') | Out-Null; $script:fails++ }
else {
    $fakeCreated = (Get-Date).AddDays(-1).ToString('o')
    $mismatchIdent = @(, [pscustomobject]@{ pid = $stub3.Id; created = $fakeCreated; name = 'python.exe' })
    $rep3 = Get-RecoveryReport $mismatchIdent
    Check 'stub3: live pid with WRONG created time -> pid_reused' (@($rep3.rows | Where-Object { $_.post_status -eq 'pid_reused' }).Count -eq 1) ((@($rep3.rows) | ForEach-Object { $_.post_status }) -join ',')
    Check 'stub3: pid_reused does NOT fail acceptance' ($rep3.all_gone) 'pid_reused incorrectly failed acceptance'
    try { taskkill /PID $stub3.Id /T /F 2>$null | Out-Null } catch { }
}

# --- stub 3: query failure -> query_failed + acceptance FAIL --------------------
# simulate a CIM query failure via the -CimLookup test-only seam; the function
# must classify it query_failed and FAIL acceptance (never silently gone)
$stub4 = New-StubPython 20 'queryfail'
if (-not $stub4) { Write-Host '[FAIL] stub4 failed to launch'; $rows.Add('stub4-launch,FAIL') | Out-Null; $script:fails++ }
else {
    $ident4 = @(Get-RecoveryIdentity $stub4.Id)
    $rep4 = Get-RecoveryReport $ident4 -CimLookup { param($pid) throw 'simulated CIM failure' }
    Check 'stub4: simulated CIM failure -> query_failed' (@($rep4.rows | Where-Object { $_.post_status -eq 'query_failed' }).Count -ge 1) ((@($rep4.rows) | ForEach-Object { $_.post_status }) -join ',')
    Check 'stub4: query_failed FAILS acceptance' (-not $rep4.all_gone) 'query failure was treated as gone'
    try { taskkill /PID $stub4.Id /T /F 2>$null | Out-Null } catch { }
}

# --- cleanup confirmation ---------------------------------------------------------
Start-Sleep -Milliseconds 800
$stubIds = @()
foreach ($s in @($stub1, $stub2, $stub3, $stub4)) { if ($s) { $stubIds += $s.Id } }
$leftover = @(Get-Process | Where-Object { $_.ProcessName -like 'python*' -and $_.Id -in $stubIds })
Check 'cleanup: all stub pythons terminated' ($leftover.Count -eq 0) ($leftover.Count.ToString() + ' stubs survived')

'check,verdict' | Set-Content (Join-Path $OutDir 'matrix.csv') -Encoding ASCII
$rows | ForEach-Object { Add-Content (Join-Path $OutDir 'matrix.csv') $_ -Encoding ASCII }
Get-Content (Join-Path $OutDir 'matrix.csv')
if ($script:fails -gt 0) { Write-Host ("[FAIL] R4 recovery stubs: {0} failed" -f $script:fails); exit 1 }
Write-Host '[PASS] R4 recovery stubs'
exit 0
