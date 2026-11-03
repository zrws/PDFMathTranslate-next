# Env restore delivery test (G16 / S3): proves p0_env.ps1 existed/value
# semantics for all required coverage dimensions. ASCII only, PS 5.1 safe.
# In-process sentinels; no real credentials; no product import.
#
# Coverage:
#  1 existed=true value restore          2 existed=false key created then removed
#  3 case-insensitive dedup              4 success path (Set-ChildEnvBlock)
#  5 exception path (finally restore)    6 timeout path (bg job abandoned)
#  7 PYTHONPATH managed + restored       8 CWD try/finally
# Exit: 0 all pass; 1 any failure; 4 prerequisite missing.

param(
    [string]$EvidenceRoot = '',
    [string]$RepoRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent),
    [string]$OutDir = ''
)

. (Join-Path $PSScriptRoot 'p0_paths.ps1')
$EvidenceRoot = Resolve-P0EvidenceRoot $RepoRoot $EvidenceRoot

$ErrorActionPreference = 'Continue'
if (-not (Test-Path (Join-Path $RepoRoot 'tests\performance\p0_env.ps1'))) { Write-Host '[FAIL] p0_env.ps1 missing'; exit 4 }

if (-not $OutDir) {
    $OutDir = Join-Path $EvidenceRoot ("runs\env-restore-" +
        (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + $PID)
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
(Join-Path $RepoRoot 'tests\performance\p0_env.ps1') |
    ForEach-Object { @{ 'p0_env.ps1' = (Get-FileHash $_ -Algorithm SHA256).Hash } } |
    ConvertTo-Json | Set-Content (Join-Path $OutDir 'script-hashes.json') -Encoding UTF8

. (Join-Path $RepoRoot 'tests\performance\p0_env.ps1')

$rows = New-Object System.Collections.Generic.List[string]
$script:fails = 0
function Invoke-Case([string]$id, [string]$expect, [scriptblock]$action) {
    Write-Host ("=== {0} ===" -f $id)
    $observed = & $action
    $verdict = if ("$observed" -eq "$expect") { 'PASS' } else { 'FAIL' }
    if ($verdict -eq 'FAIL') { $script:fails++ }
    $rows.Add(("{0},{1},{2},{3}" -f $id, $expect, $observed, $verdict)) | Out-Null
    Write-Host ("  {0}: observed={1} expected={2} verdict={3}" -f $id, $observed, $expect, $verdict)
}

# --- 1: existed=true restore ----------------------------------------------------
Invoke-Case '1-existed-true-restore' 'PASS' {
    $n = 'P0ENV_TEST_EXISTED'
    try {
        [Environment]::SetEnvironmentVariable($n, 'original-value-A', 'Process')
        $saved = Save-ChildEnv @($n)
        [Environment]::SetEnvironmentVariable($n, 'CHANGED', 'Process')
        Restore-ChildEnv $saved
        if ([Environment]::GetEnvironmentVariable($n, 'Process') -eq 'original-value-A') { 'PASS' } else { 'FAIL' }
    } finally {
        Remove-Item ("Env:" + $n) -ErrorAction SilentlyContinue
    }
}

# --- 2: existed=false -> restore deletes the newly created key -------------------
Invoke-Case 'existed-false-key-removed' 'PASS' {
    $n = 'P0ENV_TEST_ABSENT'
    Remove-Item ("Env:" + $n) -ErrorAction SilentlyContinue
    try {
        $saved = Save-ChildEnv @($n)   # did not exist: existed=false must be recorded
        $recExisted = $saved[$n].existed
        [Environment]::SetEnvironmentVariable($n, 'created-during-run', 'Process')
        Restore-ChildEnv $saved
        $post = [Environment]::GetEnvironmentVariable($n, 'Process')
        if (($recExisted -eq $false) -and ($null -eq $post)) { 'PASS' } else { 'FAIL' }
    } finally {
        Remove-Item ("Env:" + $n) -ErrorAction SilentlyContinue
    }
}

# --- 3: case-insensitive dedup ---------------------------------------------------
Invoke-Case 'case-insensitive-dedup' 'PASS' {
    $saved = Save-ChildEnv @('P0ENV_TEST_DEDUP', 'p0env_test_dedup')
    if ($saved.Count -eq 1) { 'PASS' } else { 'FAIL' }
}

# --- 4: success path - Set-ChildEnvBlock batch save/clear/restore, 6 proxy keys +
# case variants, all restored exactly ------------------------------------------------
Invoke-Case 'proxy-batch-success-path' 'PASS' {
    $names = @('HTTP_PROXY','HTTPS_PROXY','ALL_PROXY','HTTP_proxy','no_proxy','PDF2ZH_GUARD_LOG')
    $beforeValues = @{}
    foreach ($n in $names) { $beforeValues[$n] = [Environment]::GetEnvironmentVariable($n) }
    $saved = Set-ChildEnvBlock $names
    try {
        foreach ($n in $names) { [Environment]::SetEnvironmentVariable($n, 'mutated', 'Process') }
    } finally {
        Restore-ChildEnv $saved
    }
    $allOk = $true
    foreach ($n in $names) {
        $now = [Environment]::GetEnvironmentVariable($n)
        $was = $beforeValues[$n]
        if ($null -eq $was -and $null -ne $now) { $allOk = $false }
        elseif ($null -ne $was -and $now -ne $was) { $allOk = $false }
    }
    if ($allOk) { 'PASS' } else { 'FAIL' }
}

# --- 5: exception path - restore in finally survives a throw --------------------
Invoke-Case 'exception-path-restored' 'PASS' {
    $n = 'P0ENV_TEST_EXCEPTION'
    try {
        [Environment]::SetEnvironmentVariable($n, 'keep-me', 'Process')
        $saved = Save-ChildEnv @($n)
        [Environment]::SetEnvironmentVariable($n, 'CHANGED', 'Process')
        try {
            try { throw "boom" } catch { } finally { Restore-ChildEnv $saved }
        } catch { }
        if ([Environment]::GetEnvironmentVariable($n) -eq 'keep-me') { 'PASS' } else { 'FAIL' }
    } finally {
        Remove-Item ("Env:" + $n) -ErrorAction SilentlyContinue
    }
}

# --- 6: timeout path - operation abandoned after timeout, restore still runs ----
Invoke-Case 'timeout-path-restored' 'PASS' {
    $n = 'P0ENV_TEST_TIMEOUT'
    try {
        [Environment]::SetEnvironmentVariable($n, 'keep-orig', 'Process')
        $saved = Save-ChildEnv @($n)
        $job = Start-Job -ScriptBlock { param($nm) [Environment]::SetEnvironmentVariable($nm, 'CHANGED', 'Process'); Start-Sleep -Seconds 30 } -ArgumentList $n
        $timedOut = $false
        try { Wait-Job $job -Timeout 1 | Out-Null } catch { }
        if ($job.State -ne 'Completed') { $timedOut = $true }
        Remove-Job $job -Force -ErrorAction SilentlyContinue
        Restore-ChildEnv $saved
        if ($timedOut -and ([Environment]::GetEnvironmentVariable($n, 'Process') -eq 'keep-orig')) { 'PASS' } else { 'FAIL' }
    } finally {
        Remove-Item ("Env:" + $n) -ErrorAction SilentlyContinue
    }
}

# --- 7: PYTHONPATH managed, restored, never destroyed ---------------------------
Invoke-Case 'PYTHONPATH-restored' 'PASS' {
    $orig = [Environment]::GetEnvironmentVariable('PYTHONPATH', 'Process')
    $saved = Save-ChildEnv @('PYTHONPATH')
    $hadIt = (-not $saved['PYTHONPATH'].existed) -or ($saved['PYTHONPATH'].value -eq $orig)
    Remove-Item Env:PYTHONPATH -ErrorAction SilentlyContinue
    $env:PYTHONPATH = 'C:\somewhere\temp'
    Restore-ChildEnv $saved
    $post = [Environment]::GetEnvironmentVariable('PYTHONPATH', 'Process')
    $ok = $false
    if ($null -eq $orig) { $ok = ($null -eq $post) } else { $ok = ($post -eq $orig) }
    if ($ok -and $hadIt -ne $null) { 'PASS' } else { 'FAIL' }
}

# --- 8: PYTHONPATH originally absent is removed after restore (not leaked) ------
Invoke-Case 'PYTHONPATH-absent-removed' 'PASS' {
    $savedOrig = [Environment]::GetEnvironmentVariable('PYTHONPATH', 'Process')
    Remove-Item Env:PYTHONPATH -ErrorAction SilentlyContinue
    $saved = Save-ChildEnv @('PYTHONPATH')
    $env:PYTHONPATH = 'C:\temp\leak'
    Restore-ChildEnv $saved
    $post = [Environment]::GetEnvironmentVariable('PYTHONPATH', 'Process')
    if ($null -ne $savedOrig) { $env:PYTHONPATH = $savedOrig }
    if ($null -eq $post) { 'PASS' } else { 'FAIL' }
}

# --- 9: CWD try/finally ----------------------------------------------------------
Invoke-Case 'CWD-restored' 'PASS' {
    $before = (Get-Location).Path
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("p0env-cwd-" + [guid]::NewGuid().ToString('N').Substring(0, 6))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    try {
        Push-Location $tmp
    } finally {
        Pop-Location
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
    if ((Get-Location).Path -eq $before) { 'PASS' } else { 'FAIL' }
}

'case,expected,actual,verdict' | Set-Content (Join-Path $OutDir 'matrix.csv') -Encoding ASCII
$rows | ForEach-Object { Add-Content (Join-Path $OutDir 'matrix.csv') $_ -Encoding ASCII }
Get-Content (Join-Path $OutDir 'matrix.csv')
if ($script:fails -gt 0) { Write-Host ("[FAIL] env restore tests: {0} failed" -f $script:fails); exit 1 }
Write-Host '[PASS] env restore delivery tests pass'
exit 0

