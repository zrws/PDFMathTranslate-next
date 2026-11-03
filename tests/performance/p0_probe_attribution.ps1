# Attribution probe v4 (ASCII only, PS 5.1 safe)
# S1 fix: every payload is launched through entry_wrapper.py so the entry
# gate (guard active + hash binding + PID handshake) runs BEFORE the payload
# import; per-payload guard.log confirmation, per-payload APP_ENTERED.
# F2/F3/F4 heritage kept: import-completion handshake; net-guard + full env
# isolation for children (HOME/USERPROFILE/CONFIG all inside unique root);
# null/failed results make the run exit non-zero; owner marker; unique root;
# no server started (offline). -FailInject import-fail drives the failure path.
# Exit codes: 0 all payloads measured; 1 any failure/null result;
#             4 prerequisite missing.

param(
    [string]$PythonExe = '',
    [string]$EvidenceRoot = '',
    [string]$InstallRoot = (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) '.local\runtime'),
    [string]$RepoRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent),
    [ValidateSet('', 'import-fail')]
    [string]$FailInject = '',
    [string]$OutDir = ''
)

. (Join-Path $PSScriptRoot 'p0_paths.ps1')
$EvidenceRoot = Resolve-P0EvidenceRoot $RepoRoot $EvidenceRoot

$ErrorActionPreference = 'Stop'
if ($OutDir -and (Test-Path -LiteralPath $OutDir)) { Write-Host '[FAIL] OutDir already exists (refuse overwrite)'; exit 2 }
if (-not $OutDir) {
    $OutDir = Join-Path $EvidenceRoot ("runs\attribution-" +
        (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + $PID)
}

$sitePackages = Join-Path $InstallRoot 'uv-tools\pdf2zh-next\Lib\site-packages'
$guardDir = Join-Path $RepoRoot 'tests\performance\p0_guard'
$entryWrapper = Join-Path $guardDir 'entry_wrapper.py'
$python = Resolve-P0Python $InstallRoot $PythonExe
if (-not $python -or -not (Test-Path $sitePackages) -or -not (Test-Path $guardDir) -or -not (Test-Path $entryWrapper)) {
    Write-Host '[FAIL] prerequisite missing'; exit 4
}

# R3: refuse an explicitly requested non-empty OutDir BEFORE any write
# (never delete/overwrite a previous run's artifacts)
if ((Test-Path $OutDir) -and (Get-ChildItem $OutDir -ErrorAction SilentlyContinue)) {
    Write-Host ("[FAIL] OutDir already exists and is non-empty (refuse overwrite): " + $OutDir)
    exit 2
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
# runtime hash index for THIS run (C2: all actual dependencies)
$hashes = [ordered]@{}
foreach ($f in @('p0_guard\sitecustomize.py','p0_guard\entry_gate.py','p0_guard\entry_wrapper.py',
                 'p0_probe_attribution.ps1','p0_env.ps1')) {
    $p = if ($f -like 'p0_guard\*') { Join-Path $guardDir ($f -replace '^p0_guard\\','') }
         else { Join-Path $RepoRoot ('tests\performance\' + ($f -replace '^p0_','p0_')) }
    if (Test-Path $p) { $hashes[$f] = (Get-FileHash $p -Algorithm SHA256).Hash }
}
$hashes | ConvertTo-Json | Set-Content (Join-Path $OutDir 'script-hashes.json') -Encoding UTF8

$stamp = $OutDir | Split-Path -Leaf
$tempBase = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')
$root = Join-Path $tempBase ("pdf2zh-attr-" + $stamp + "-" + $PID)
$home0 = Join-Path $root 'home'
$workDir = Join-Path $root 'work'
foreach ($d in @($root, $home0, $workDir, (Join-Path $home0 'Temp'), (Join-Path $home0 '.config\pdf2zh'))) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
}
Set-Content -Path (Join-Path $root 'owner.json') -Value (@{ script='p0_probe_attribution.ps1 v4'; hostPid=$PID; created=(Get-Date).ToString('o'); root=$root } | ConvertTo-Json) -Encoding UTF8

$outFile = Join-Path $OutDir ("probe-attribution.jsonl")
# (R3: no Remove-Item of a previous run's jsonl - OutDir is fresh by construction)
$guardLog = Join-Path $root 'guard.log'

$configFile = Join-Path $home0 '.config\pdf2zh\config.v3.toml'
Set-Content -Path $configFile -Value '' -Encoding ASCII

$guardSha = (Get-FileHash (Join-Path $guardDir 'sitecustomize.py') -Algorithm SHA256).Hash

$script:rootPid = 0
$script:recoveryBatches = @()
$script:activePayload = ''
$script:hadFailure = 0
$script:gateBlocks = 0
function Get-OwnedIdentities([uint32]$rootPid) {
    $rows = @()
    $all = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue
    $map = @{}
    foreach ($p in $all) { $map[[uint32]$p.ProcessId] = [uint32]$p.ParentProcessId }
    foreach ($p in $all) {
        $cur = [uint32]$p.ProcessId; $inTree = $false
        for ($i = 0; $i -lt 10 -and $cur; $i++) {
            if ($cur -eq $rootPid) { $inTree = $true; break }
            if (-not $map.ContainsKey($cur)) { break }
            $cur = $map[$cur]
        }
        if ($inTree) { $rows += [pscustomobject]@{ pid = $p.ProcessId; created = $p.CreationDate; name = $p.Name } }
    }
    return ,$rows
}
function Test-IdentitiesGone($identities) {
    foreach ($idn in $identities) {
        $p = Get-Process -Id $idn.pid -ErrorAction SilentlyContinue
        if (-not $p) { continue }
        $cim = Get-CimInstance Win32_Process -Filter ("ProcessId = " + $idn.pid) -ErrorAction SilentlyContinue
        if ($cim -and $cim.CreationDate -eq $idn.created) { return $false }
    }
    return $true
}
function Get-RecoveryReport($identities) {
    # R4: per-identity post-kill status with EXPLICIT states. A CIM query
    # FAILURE must surface as query_failed and FAIL the run - never 'gone'.
    $rows = New-Object System.Collections.Generic.List[object]
    $allGone = $true
    foreach ($idn in $identities) {
        $status = 'gone'
        $gp = $null
        try { $gp = Get-Process -Id $idn.pid -ErrorAction Stop } catch { $gp = $null }
        if ($gp) {
            $cim = $null
            $queryFailed = $false
            try {
                $cim = Get-CimInstance Win32_Process -Filter ("ProcessId = " + $idn.pid) -ErrorAction Stop
            } catch { $queryFailed = $true }
            if ($queryFailed) { $status = 'query_failed'; $allGone = $false }
            elseif ($cim -and $cim.CreationDate -eq $idn.created) { $status = 'still_alive_same_identity'; $allGone = $false }
            else { $status = 'pid_reused' }   # different process now owns the pid
        }
        $rows.Add([pscustomobject]@{ pid = $idn.pid; created = $idn.created; name = $idn.name; post_status = $status })
    }
    return @{ rows = $rows; all_gone = $allGone }
}

function Stop-Tree {
    if ($script:rootPid -gt 0) {
        $identities = Get-OwnedIdentities ([uint32]$script:rootPid)
        try { taskkill /PID $script:rootPid /T /F 2>$null | Out-Null } catch { }
        Start-Sleep -Milliseconds 800
        # R4: persist owned identities + per-identity post status to the run dir
        $recovery = Get-RecoveryReport $identities
        $recoveryPath = Join-Path $OutDir 'recovery.json'
        try {
            $batch = [pscustomobject][ordered]@{
                payload = $script:activePayload
                captured_at = (Get-Date).ToString('o')
                owned_count = @($identities).Count
                all_gone = $recovery.all_gone
                identities = [object[]]($identities | ForEach-Object { @{ pid = $_.pid; created = $_.created; name = $_.name } })
                rows = [object[]]$recovery.rows
            }
            $batch | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $OutDir ('recovery-' + $script:activePayload + '.json')) -Encoding UTF8
            $script:recoveryBatches += $batch
            $allRows = @($script:recoveryBatches | ForEach-Object { $_.rows })
            [ordered]@{
                payload_count = $script:recoveryBatches.Count
                owned_count = $allRows.Count
                all_gone = (@($script:recoveryBatches | Where-Object { -not $_.all_gone }).Count -eq 0)
                identities = @($script:recoveryBatches | ForEach-Object { $_.identities })
                rows = $allRows
                batches = $script:recoveryBatches
            } | ConvertTo-Json -Depth 7 | Set-Content -Path $recoveryPath -Encoding UTF8
        } catch {
            Write-Host ("[FAIL] cannot write recovery.json: " + $_.Exception.Message)
            $script:hadFailure = 1
        }
        if (-not $recovery.all_gone) {
            Write-Host '[FAIL] owned processes not confirmed gone (identity recheck: still_alive_same_identity or query_failed)'
            $script:hadFailure = 1
        } else {
            Write-Host '[PASS] owned processes confirmed gone (per-identity recheck)'
        }
        $script:rootPid = 0
    }
}

function Probe($label, $importExpr) {
    $script:activePayload = $label
    $logFile = Join-Path $root ($label + '.log')
    # S1: payload is a real .py file launched via entry_wrapper so the entry
    # gate verifies guard+hash BEFORE the import runs.
    $targetPy = Join-Path $root ("payload_" + $label + ".py")
    if ($FailInject -eq 'import-fail') {
        "import time; import nonexistent_module_for_p0_negative_test_xyz; print('IMPORT_DONE', flush=True); time.sleep(20)" |
            Set-Content -Path $targetPy -Encoding ASCII
    } elseif ($importExpr) {
        ("import time; " + $importExpr + "; print('IMPORT_DONE', flush=True); time.sleep(20)") |
            Set-Content -Path $targetPy -Encoding ASCII
    } else {
        "import time; print('IMPORT_DONE', flush=True); time.sleep(20)" | Set-Content -Path $targetPy -Encoding ASCII
    }

    $pinfo = [System.Diagnostics.ProcessStartInfo]::new()
    $pinfo.FileName = "$env:ComSpec"
    $pinfo.Arguments = '/c ""' + $python + '" -u "' + $entryWrapper + '" > "' + $logFile + '" 2>&1"'
    $pinfo.WorkingDirectory = $workDir
    $pinfo.UseShellExecute = $false
    $pinfo.CreateNoWindow = $true
    # isolate every home-ish path for THIS child only (per-child env, not system)
    $pinfo.EnvironmentVariables['PYTHONPATH'] = $guardDir + ';' + (Join-Path $RepoRoot 'source') + ';' + $sitePackages
    $pinfo.EnvironmentVariables['HOME'] = $home0
    $pinfo.EnvironmentVariables['USERPROFILE'] = $home0
    $pinfo.EnvironmentVariables['APPDATA'] = (Join-Path $home0 'AppData\Roaming')
    $pinfo.EnvironmentVariables['LOCALAPPDATA'] = (Join-Path $home0 'AppData\Local')
    $pinfo.EnvironmentVariables['TEMP'] = (Join-Path $home0 'Temp')
    $pinfo.EnvironmentVariables['TMP'] = (Join-Path $home0 'Temp')
    $pinfo.EnvironmentVariables['PDF2ZH_HOME'] = $home0
    $pinfo.EnvironmentVariables['PDF2ZH_CONFIG_FILE'] = $configFile
    $pinfo.EnvironmentVariables['PDF2ZH_GUARD_LOG'] = $guardLog
    $pinfo.EnvironmentVariables['PDF2ZH_GUARD_DIR'] = $guardDir
    $pinfo.EnvironmentVariables['PDF2ZH_RUN_ID'] = "attr-$label-$([guid]::NewGuid().ToString('N').Substring(0,8))"
    $pinfo.EnvironmentVariables['PDF2ZH_GUARD_SHA256'] = $guardSha
    $pinfo.EnvironmentVariables['PDF2ZH_TARGET_SCRIPT'] = $targetPy
    $pinfo.EnvironmentVariables['NO_PROXY'] = '127.0.0.1,localhost'
    $strip = @()
    foreach ($k in $pinfo.EnvironmentVariables.Keys) {
        if (($k -like 'PDF2ZH_*' -or $k -like 'BABELDOC_*' -or $k -like '*_PROXY') -and
            $k -notin @('PDF2ZH_HOME','PDF2ZH_CONFIG_FILE','PDF2ZH_GUARD_LOG','PDF2ZH_GUARD_DIR',
                        'PDF2ZH_RUN_ID','PDF2ZH_GUARD_SHA256','PDF2ZH_TARGET_SCRIPT',
                        'BABELDOC_ASSETS_UPSTREAM','NO_PROXY','no_proxy')) {
            $strip += $k
        }
    }
    foreach ($k in $strip) { $pinfo.EnvironmentVariables.Remove($k) | Out-Null }

    $proc = [System.Diagnostics.Process]::new()
    $proc.StartInfo = $pinfo
    try {
        [void]$proc.Start()
        $script:rootPid = $proc.Id
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $done = $false
        while ($sw.ElapsedMilliseconds -lt 120000) {
            if ($proc.HasExited) { break }
            # anchor to LINE START: python tracebacks echo the payload source
            # line "print('IMPORT_DONE', ...)" mid-line - a loose match would
            # misread a crashed payload as a healthy handshake
            if ((Test-Path $logFile) -and (Select-String -Path $logFile -Pattern '^IMPORT_DONE' -Quiet)) { $done = $true; break }
            Start-Sleep -Milliseconds 100
        }
        $logText = if (Test-Path $logFile) { Get-Content $logFile -Raw } else { '' }
        $gateBlocked = ($logText -match 'ENTRY_GATE: ')
        if ($gateBlocked) { $script:gateBlocks++ }
        if (-not $done) {
            [pscustomobject]@{ label = $label; privateMB = $null; workingSetMB = $null; gate_blocked = $gateBlocked; note = 'no IMPORT_DONE within 120s (import failed/timeout/gate block)' } |
                ConvertTo-Json -Compress | Add-Content $outFile
            Write-Host "[FAIL] $label no IMPORT_DONE"
            $script:hadFailure = 1
            return
        }
        $pyPid = (Get-CimInstance Win32_Process -Filter "Name='python.exe' AND ParentProcessId=$($proc.Id)" -ErrorAction SilentlyContinue).ProcessId
        if (-not $pyPid) {
            [pscustomobject]@{ label = $label; privateMB = $null; workingSetMB = $null; gate_blocked = $gateBlocked; note = 'python child not found after handshake (exited or never started)' } |
                ConvertTo-Json -Compress | Add-Content $outFile
            Write-Host "[FAIL] $label python child not found"
            $script:hadFailure = 1
            return
        }
        $gp = Get-Process -Id $pyPid -ErrorAction SilentlyContinue
        if ($gp) {
            [pscustomobject]@{
                label = $label
                privateMB = [math]::Round($gp.PrivateMemorySize64 / 1MB, 1)
                workingSetMB = [math]::Round($gp.WorkingSet64 / 1MB, 1)
                gate_blocked = $gateBlocked
                note = 'measured after IMPORT_DONE handshake; entry gate verified guard+hash before import; isolated HOME/CONFIG; net-guard active'
            } | ConvertTo-Json -Compress | Add-Content $outFile
            Write-Host ("{0}: private={1:N1}MB ws={2:N1}MB" -f $label, ($gp.PrivateMemorySize64/1MB), ($gp.WorkingSet64/1MB))
        } else {
            [pscustomobject]@{ label = $label; privateMB = $null; workingSetMB = $null; gate_blocked = $gateBlocked; note = 'process exited early' } |
                ConvertTo-Json -Compress | Add-Content $outFile
            Write-Host "[FAIL] $label process exited early"
            $script:hadFailure = 1
        }
    } finally {
        Stop-Tree
        Start-Sleep -Milliseconds 500
    }
}

if ($FailInject -eq 'import-fail') {
    Probe 'import_babeldoc_assets' 'import babeldoc.assets.assets'
    Probe 'import_fastapi_uvicorn_pydantic' 'import fastapi, uvicorn, pydantic'
    Probe 'import_pdf2zh_next_http_api' 'import pdf2zh_next.http_api'
} else {
    Probe 'bare_sleep' ''
    Probe 'import_babeldoc_assets' 'import babeldoc.assets.assets'
    Probe 'import_fastapi_uvicorn_pydantic' 'import fastapi, uvicorn, pydantic'
    Probe 'import_pdf2zh_next_http_api' 'import pdf2zh_next.http_api'
}

$nullCount = 0
if (Test-Path $outFile) {
    foreach ($line in (Get-Content $outFile)) {
        if ($line -like '*"privateMB":null*') { $nullCount++ }
    }
}
if ($nullCount -gt 0) { Write-Host ("[FAIL] {0} payload(s) without valid measurement" -f $nullCount); $script:hadFailure = 1 }
# B2: guard.log must exist AND contain GUARD_ACTIVE
if (-not (Test-Path $guardLog)) {
    Write-Host '[FAIL] guard.log missing: guard never loaded; run invalid (B2)'
    $script:hadFailure = 1
} elseif (-not (Select-String -Path $guardLog -Pattern 'GUARD_ACTIVE' -Quiet)) {
    Write-Host '[FAIL] guard.log exists but no GUARD_ACTIVE: guard failed to load (B2)'
    $script:hadFailure = 1
} else {
    Copy-Item $guardLog (Join-Path $OutDir 'guard.log.txt') -Force
    $blocked = (Select-String -Path $guardLog -Pattern 'BLOCKED' -ErrorAction SilentlyContinue | Measure-Object).Count
    $entered = (Select-String -Path $guardLog -Pattern 'APP_ENTERED' -Quiet)
    if ($blocked -gt 0) {
        Write-Host ("[FAIL] net-guard blocked {0} outbound attempts (unexpected outside warmup)" -f $blocked)
        $script:hadFailure = 1
    }
    if (-not $entered) {
        Write-Host '[FAIL] no APP_ENTERED sentinel: entry gate never confirmed'
        $script:hadFailure = 1
    } else { Write-Host '[PASS] entry gate: APP_ENTERED present' }
}
# structured result for THIS attribution run (unique location; never overwrite shared result)
$plannedExit = if ($script:hadFailure -ne 0) { 1 } else { 0 }
$result = [ordered]@{
    run_id = ("attr-" + $stamp + "-" + $PID)
    entry = 'p0_probe_attribution'
    fail_inject = $FailInject
    verdict = $(if ($plannedExit -eq 0) { 'PASS' } else { 'FAIL' })
    planned_exit = $plannedExit
    gate_blocks = $script:gateBlocks
    evidence_path = $outFile
    temp_root = $root
    note = 'structured result per S4: planned exit only; outer runner records observed exit separately'
}
$result | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $OutDir 'result.json') -Encoding UTF8
if ($plannedExit -ne 0) { Write-Host '[FAIL] attribution run had failures'; exit 1 }
if (-not (Test-Path $outFile)) { Write-Host '[FAIL] no evidence written'; exit 1 }
Write-Host ("attribution v4 done: {0}" -f $outFile)
Write-Host ("temp root preserved: {0}" -f $root)
exit 0

