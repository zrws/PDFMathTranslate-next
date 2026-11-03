# Per-process memory probe v3 (ASCII only, PS 5.1 safe)
# F2/F3/F4 remediation: cache staged AND integrity-verified before start
# (no silent downloads); net-guard via sitecustomize; PDF2ZH_CONFIG_FILE
# isolated; env whitelist; no early exit 0 inside try; sample-count enforced;
# leftover/port failures change the final exit code; owner marker; unique root.
# Exit codes: 0 ok; 1 failure; 3 port conflict; 4 prerequisite missing.

param(
    [string]$InstallRoot = 'D:\paper\pdf2zh-install-test',
    [string]$RepoRoot = 'D:\paper\PDFMathTranslate-next',
    [int]$Port = 7916,
    [int]$SampleSeconds = 30,
    [string]$OutDir = '',
    [ValidateSet('', 'midrun-exception')]
    [string]$FailInject = ''
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http   # C2: required for HttpClientHandler below
. (Join-Path $RepoRoot 'tests\performance\p0_result.ps1')   # S4: shared result writer
. (Join-Path $RepoRoot 'tests\performance\p0_env.ps1')      # S3: env save/restore
# R4: started_at is the REAL run window start (now); ended_at is set in the
# finally after recovery; result_built_at is separately the result build time
$runWindowStart = (Get-Date).ToString('o')
$startIso = $runWindowStart

$pyBase = Join-Path $InstallRoot 'uv-python'
$sitePackages = Join-Path $InstallRoot 'uv-tools\pdf2zh-next\Lib\site-packages'
$sourceDir = Join-Path $RepoRoot 'source'
$scriptPy = Join-Path $RepoRoot 'start-webui.py'
$webuiDir = Join-Path $RepoRoot 'webui'
$guardDir = Join-Path $RepoRoot 'tests\performance\p0_guard'
$cacheSrc = Join-Path $InstallRoot 'home\.cache\babeldoc'
foreach ($p in @($InstallRoot, $pyBase, $sitePackages, $sourceDir, $scriptPy, $guardDir)) {
    if (-not (Test-Path $p)) { Write-Host "[FAIL] missing: $p"; exit 4 }
}
$python = Get-ChildItem $pyBase -Recurse -Filter python.exe | Select-Object -First 1 -ExpandProperty FullName
if (-not $python) { Write-Host '[FAIL] python.exe not found'; exit 4 }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
if (-not $OutDir) {
    $OutDir = Join-Path $RepoRoot ("docs\verification\native-desktop\r2-integrated-20261003-01\runs\perprocess-" +
        $stamp + '-' + $PID)
}
$tempBase = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')
$root = Join-Path $tempBase ("pdf2zh-probe-pp-" + $stamp + "-" + $PID)
$home0 = Join-Path $root 'home'
$workDir = Join-Path $root 'work'
foreach ($d in @($root, $home0, $workDir, (Join-Path $home0 'Temp'), (Join-Path $home0 '.config\pdf2zh'))) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
}
Set-Content -Path (Join-Path $root 'owner.json') -Value (@{ script='p0_probe_perprocess.ps1 v3'; hostPid=$PID; created=(Get-Date).ToString('o'); root=$root } | ConvertTo-Json) -Encoding UTF8

$runDir = $OutDir
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$outFile = Join-Path $runDir ("probe-pp.jsonl")
# S4: structured result goes to the run's OWN directory; the shared
# docs/verification/native-desktop/result.json is no longer written (no
# cross-run overwrite). RunId reuse must not silently overwrite either.
$resultPath = Join-Path $runDir 'result.json'
if (Test-Path $resultPath) { Write-Host ("[FAIL] result.json already exists in run dir (RunId reuse refused): " + $resultPath); exit 2 }
$guardLog = Join-Path $root 'guard.log'

# port pre-check
$l = [System.Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $Port)
try { $l.Start(); $l.Stop() } catch { Write-Host "[FAIL] port $Port in use"; exit 3 }

# stage + integrity-verify babeldoc cache (F3; empty home previously caused real downloads)
$dstCache = Join-Path $home0 '.cache\babeldoc'
if (-not (Test-Path $cacheSrc)) { Write-Host '[FAIL] babeldoc cache missing; offline mode refuses download'; exit 4 }
robocopy $cacheSrc $dstCache /E /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { Write-Host ("[FAIL] robocopy rc=" + $LASTEXITCODE); exit 4 }
# C1: authoritative asset verification (SHA3-256 from locked babeldoc metadata)
. (Join-Path $RepoRoot 'tests\performance\p0_asset_check.ps1')
$assetOk = Invoke-AssetCheck -CacheDir $dstCache -InstallRoot $InstallRoot -IsolatedHome $home0 
if (-not $assetOk) { Write-Host '[FAIL] authoritative asset check: missing/corrupt; refusing to start'; exit 4 }
Write-Host '[PASS] authoritative asset check (locked babeldoc SHA3-256)'

# copy consistency check (secondary)
$srcList = Get-ChildItem $cacheSrc -Recurse -File
$bad = 0
foreach ($f in $srcList) {
    $rel = $f.FullName.Substring($cacheSrc.Length).TrimStart('\')
    $dst = Join-Path $dstCache $rel
    if (-not (Test-Path $dst)) { $bad++; continue }
    if ((Get-FileHash $f.FullName -Algorithm SHA256).Hash -ne (Get-FileHash $dst -Algorithm SHA256).Hash) { $bad++ }
}
if ($bad -gt 0 -or (Get-ChildItem $dstCache -Recurse -File | Measure-Object).Count -ne $srcList.Count) {
    Write-Host ("[FAIL] cache integrity check failed (mismatch/missing: " + $bad + ")"); exit 4
}
Write-Host ("cache verified: {0} files byte-identical" -f $srcList.Count)

$configFile = Join-Path $home0 '.config\pdf2zh\config.v3.toml'
Set-Content -Path $configFile -Value '' -Encoding ASCII

$script:rootPid = 0
$script:finalRc = 0
$script:sampleCount = 0
$script:ownedProcesses = New-Object System.Collections.Generic.List[object]   # deduped identities
$script:processesRecovered = $null   # S4: from identity recheck, NOT from port release
$script:identityRecheckPassed = $null
$script:recoveryDetails = New-Object System.Collections.Generic.List[object]
function Get-OwnedIdentities([uint32]$rootPid) {
    # walk ALL processes' parent chains (grandchildren included, name-agnostic)
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
function Stop-Tree {
    if ($script:rootPid -gt 0) {
        # S4/F2: recovery set is the DEDUPED identity set (pid+created unique).
        # Identities may ALREADY have been recorded by the sampling loop; merge
        # with cross-source dedup so no duplicate rows reach the result.
        $identities = Get-OwnedIdentities ([uint32]$script:rootPid)
        foreach ($idn in $identities) {
            $key = ("{0}:{1}" -f $idn.pid, $idn.created)
            $dup = $false
            foreach ($op in $script:ownedProcesses) {
                if (("{0}:{1}" -f $op.pid, $op.created) -eq $key) { $dup = $true; break }
            }
            if (-not $dup) {
                $script:ownedProcesses.Add(@{ pid = $idn.pid; name = $idn.name; created = $idn.created })
            }
        }
        try { taskkill /PID $script:rootPid /T /F 2>$null | Out-Null } catch { }
        Start-Sleep -Milliseconds 800
        # F2/G4: identity-based recheck (no name-scan, survives exited middles)
        # R4: explicit per-identity states; a CIM QUERY FAILURE is query_failed
        # and fails the run - never silently treated as gone; a pid owned by a
        # DIFFERENT process now is pid_reused (recorded, does not fail).
        $allGone = $true
        foreach ($idn in ($script:ownedProcesses | ForEach-Object { $_ })) {
            $statusPost = 'gone'
            $gp = $null
            try { $gp = Get-Process -Id $idn.pid -ErrorAction Stop } catch { $gp = $null }
            if ($gp) {
                $cim = $null
                $queryFailed = $false
                try {
                    $cim = Get-CimInstance Win32_Process -Filter ("ProcessId = " + $idn.pid) -ErrorAction Stop
                } catch { $queryFailed = $true }
                if ($queryFailed) {
                    $statusPost = 'query_failed'; $allGone = $false
                } elseif ($cim -and $cim.CreationDate -eq $idn.created) {
                    $statusPost = 'still_alive_same_identity'; $allGone = $false
                } else {
                    $statusPost = 'pid_reused'
                }
            }
            $script:recoveryDetails.Add(@{ pid = $idn.pid; created = $idn.created; post_status = $statusPost })
        }
        $script:identityRecheckPassed = $allGone
        # S4: processes_recovered is bound to the identity recheck result
        $script:processesRecovered = $allGone
        if (-not $allGone) {
            Write-Host '[FAIL] owned processes survived termination (identity recheck)'
            $script:finalRc = 1
        }
        $script:rootPid = 0
    }
}

$probeFail = 0
$script:exceptionMessage = ''
$guardSha = (Get-FileHash (Join-Path $RepoRoot 'tests\performance\p0_guard\sitecustomize.py') -Algorithm SHA256).Hash
$actualGuardActive = $false
$actualGuardBlocked = 0
$actualPortReleased = $null
try {
    $pinfo = [System.Diagnostics.ProcessStartInfo]::new()
    $pinfo.FileName = "$env:ComSpec"
    $pinfo.Arguments = '/c ""' + $python + '" -u "' + (Join-Path $RepoRoot 'tests\performance\p0_guard\entry_wrapper.py') + '" > "' + (Join-Path $root 'backend.log') + '" 2>&1"'
    $pinfo.WorkingDirectory = $workDir
    $pinfo.UseShellExecute = $false
    $pinfo.CreateNoWindow = $true
    $pinfo.EnvironmentVariables['PDF2ZH_HOME'] = $home0
    $pinfo.EnvironmentVariables['PDF2ZH_CONFIG_FILE'] = $configFile
    $pinfo.EnvironmentVariables['PDF2ZH_WEBUI_DIR'] = $webuiDir
    $pinfo.EnvironmentVariables['HOME'] = $home0
    $pinfo.EnvironmentVariables['USERPROFILE'] = $home0
    $pinfo.EnvironmentVariables['APPDATA'] = (Join-Path $home0 'AppData\Roaming')
    $pinfo.EnvironmentVariables['LOCALAPPDATA'] = (Join-Path $home0 'AppData\Local')
    $pinfo.EnvironmentVariables['TEMP'] = (Join-Path $home0 'Temp')
    $pinfo.EnvironmentVariables['TMP'] = (Join-Path $home0 'Temp')
    $pinfo.EnvironmentVariables['PYTHONUTF8'] = '1'
    $pinfo.EnvironmentVariables['PYTHONPATH'] = $guardDir + ';' + $sourceDir + ';' + $sitePackages
    $pinfo.EnvironmentVariables['PDF2ZH_GUARD_LOG'] = $guardLog
    $pinfo.EnvironmentVariables['PDF2ZH_GUARD_DIR'] = $guardDir
    $pinfo.EnvironmentVariables['PDF2ZH_RUN_ID'] = "pp-$stamp-$PID"
    $pinfo.EnvironmentVariables['PDF2ZH_GUARD_SHA256'] = $guardSha
    $pinfo.EnvironmentVariables['PDF2ZH_TARGET_SCRIPT'] = $scriptPy
    $pinfo.EnvironmentVariables['PDF2ZH_TARGET_ARGS'] = "--server-port $Port"
    $pinfo.EnvironmentVariables['NO_PROXY'] = '127.0.0.1,localhost'
    $strip = @()
    foreach ($k in $pinfo.EnvironmentVariables.Keys) {
        if (($k -like 'PDF2ZH_*' -or $k -like 'BABELDOC_*' -or $k -like '*_PROXY') -and
            $k -notin @('PDF2ZH_HOME','PDF2ZH_CONFIG_FILE','PDF2ZH_WEBUI_DIR','PDF2ZH_GUARD_LOG','PDF2ZH_GUARD_DIR','PDF2ZH_RUN_ID','PDF2ZH_GUARD_SHA256','PDF2ZH_TARGET_SCRIPT','PDF2ZH_TARGET_ARGS','BABELDOC_ASSETS_UPSTREAM','NO_PROXY','no_proxy')) {
            $strip += $k
        }
    }
    foreach ($k in $strip) { $pinfo.EnvironmentVariables.Remove($k) | Out-Null }

    $proc = [System.Diagnostics.Process]::new()
    $proc.StartInfo = $pinfo
    [void]$proc.Start()
    $script:rootPid = $proc.Id

    # wait for API ready (monotonic, 200 only)
    $h = [System.Net.Http.HttpClientHandler]::new(); $h.UseProxy = $false
    $client = [System.Net.Http.HttpClient]::new($h); $client.Timeout = [TimeSpan]::FromSeconds(10)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $ready = $false
    while ($sw.ElapsedMilliseconds -lt 360000) {
        if ($proc.HasExited) { break }
        try {
            $r = $client.GetAsync("http://127.0.0.1:$Port/api/version").GetAwaiter().GetResult()
            if ([int]$r.StatusCode -eq 200) { $ready = $true; break }
        } catch { }
        Start-Sleep -Milliseconds 100
    }
    if (-not $ready) { Write-Host '[FAIL] backend not ready'; $probeFail = 1 }
    else {
        # ownership: listener must be in our tree
        $conn = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $conn) { Write-Host '[FAIL] no listener'; $probeFail = 1 }
        else {
            $map = @{}
            foreach ($p in (Get-CimInstance Win32_Process -Filter "Name = 'python.exe'")) { $map[[uint32]$p.ProcessId] = [uint32]$p.ParentProcessId }
            $cur = [uint32]$conn.OwningProcess; $inTree = ($cur -eq [uint32]$proc.Id)
            for ($i = 0; $i -lt 6 -and $cur; $i++) {
                if ($cur -eq [uint32]$proc.Id) { $inTree = $true; break }
                if (-not $map.ContainsKey($cur)) { break }
                $cur = $map[$cur]
            }
            if (-not $inTree) { Write-Host '[FAIL] listener not owned by our tree'; $probeFail = 1 }
            else {
                # sample every python process in tree, twice, SampleSeconds apart;
                # each round must yield at least one sample
                for ($round = 1; $round -le 2; $round++) {
                    $map = @{}
                    foreach ($p in (Get-CimInstance Win32_Process -Filter "Name = 'python.exe'")) { $map[[uint32]$p.ProcessId] = [uint32]$p.ParentProcessId }
                    $roundCount = 0
                    foreach ($p in $map.Keys) {
                        $inTree2 = $false
                        $c2 = $p
                        for ($i = 0; $i -lt 8 -and $c2; $i++) {
                            if ($c2 -eq [uint32]$proc.Id) { $inTree2 = $true; break }
                            if (-not $map.ContainsKey($c2)) { break }
                            $c2 = $map[$c2]
                        }
                        if (-not $inTree2) { continue }
                        $gp = Get-Process -Id $p -ErrorAction SilentlyContinue
                        if (-not $gp) { continue }
                        $cimRow = Get-CimInstance Win32_Process -Filter ("ProcessId = " + $p) -ErrorAction SilentlyContinue
                        [pscustomobject]@{
                            round = $round; pid = $p; parent = $cimRow.ParentProcessId
                            cmdline = ($cimRow.CommandLine -replace [regex]::Escape($InstallRoot), '<installroot>').Replace($root, '<isolated-root>')
                            privateMB = [math]::Round($gp.PrivateMemorySize64 / 1MB, 1)
                            workingSetMB = [math]::Round($gp.WorkingSet64 / 1MB, 1)
                            threads = $gp.Threads.Count; backend = 'repo-source'
                        } | ConvertTo-Json -Compress | Add-Content $outFile
                        $roundCount++
                        $script:sampleCount++
                        # S4: dedup by pid+created before adding to the owned set
                        $key = ("{0}:{1}" -f $p, $cimRow.CreationDate)
                        $dup = $false
                        foreach ($op in $script:ownedProcesses) {
                            if (("{0}:{1}" -f $op.pid, $op.created) -eq $key) { $dup = $true; break }
                        }
                        if (-not $dup) {
                            $script:ownedProcesses.Add(@{ pid = $p; name = 'python.exe'; created = $cimRow.CreationDate })
                        }
                    }
                    if ($roundCount -eq 0) { Write-Host ("[FAIL] round {0} produced no samples" -f $round); $probeFail = 1 }
                    if ($round -eq 1) { Start-Sleep -Seconds $SampleSeconds }
                }
            }
        }
    }
    # N04: test-only hook - inject an exception AFTER partial work so the
    # catch/finally path can be proven to still write a structured result.
    if ($FailInject -eq 'midrun-exception') {
        throw "P0_N04_INJECTED_EXCEPTION: test-only failure injection after sampling"
    }
} catch {
    # S4: main-flow exceptions are caught and recorded; the finally below has
    # already/attempts recovery; the structured result after this block records
    # the failure with a usable minimal shape even for pre-start failures.
    Write-Host ("[FAIL] unhandled exception in probe main flow: " + $_.Exception.Message)
    Write-Host ("stack: " + $_.ScriptStackTrace)
    $script:exceptionMessage = $_.Exception.Message
} finally {
    Stop-Tree
    $conn2 = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    if ($conn2) { Write-Host '[FAIL] port still listening'; $script:finalRc = 1 }
    else { Write-Host '[PASS] port released' }
    # B2: guard.log must exist AND contain GUARD_ACTIVE
    # P1-2 fix: capture ACTUAL runtime values for result.json (no hardcoding)
    if (Test-Path $guardLog) {
        $actualGuardActive = (Select-String -Path $guardLog -Pattern 'GUARD_ACTIVE' -Quiet)
        $actualGuardBlocked = (Select-String -Path $guardLog -Pattern 'BLOCKED' -ErrorAction SilentlyContinue | Measure-Object).Count
        Copy-Item $guardLog (Join-Path $runDir ('guard-' + $stamp + '.log.txt')) -Force
        Copy-Item $guardLog (Join-Path $runDir 'guard.log') -Force
    }
    if (-not (Test-Path $guardLog)) {
        Write-Host '[FAIL] guard.log missing: guard never loaded; run invalid (B2)'
        $script:finalRc = 1
    } elseif (-not $actualGuardActive) {
        Write-Host '[FAIL] guard.log exists but no GUARD_ACTIVE: guard failed to load (B2)'
        $script:finalRc = 1
    } else {
        $entryOk = ((Get-Content $guardLog -Raw) -match 'APP_ENTERED')
        if (-not $entryOk) { Write-Host '[FAIL] no APP_ENTERED sentinel: startup gate did not confirm'; $script:finalRc = 1 }
        else { Write-Host '[PASS] entry gate: APP_ENTERED present' }
        if ($actualGuardBlocked -gt 0) { Write-Host ("[FAIL] net-guard blocked {0} outbound attempts (see guard log)" -f $actualGuardBlocked); $script:finalRc = 1 }
        else { Write-Host '[PASS] net-guard: zero outbound attempts (GUARD_ACTIVE confirmed)' }
    }
    # P1-2: capture actual recovery/port status (independent observation)
    $actualPortReleased = -not (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
    Copy-Item (Join-Path $root 'backend.log') (Join-Path $runDir 'backend.log.txt') -Force -ErrorAction SilentlyContinue
    Write-Host ("temp root preserved: {0}" -f $root)
    # R4: real run window end (after recovery); result_built_at is separate
    $script:runWindowEnd = (Get-Date).ToString('o')
}

# S4: fallback is NOT deployed in perprocess measurement (guard-only);
# per authorization this must be recorded as N/A, never as a fake zero.
$fallbackHitsField = 'not_deployed'
if ($probeFail -ne 0) { $script:finalRc = 1 }
if ($script:exceptionMessage) { $script:finalRc = 1 }

# C4/T3/S4: structured result with ACTUAL runtime values, written via the
# shared p0_result.ps1 writer to THIS run's unique directory.
$result = New-RunResult -RunId ("pp-$stamp-$PID") -Entry 'p0_probe_perprocess'
$result['input_params'] = "port=$Port sampleSeconds=$SampleSeconds"
$result['fail_inject'] = $FailInject
$result['script_hashes'] = [ordered]@{
    self = (Get-FileHash $PSCommandPath -Algorithm SHA256).Hash
    asset_check = (Get-FileHash (Join-Path $RepoRoot 'tests\performance\p0_asset_check.ps1') -Algorithm SHA256).Hash
    result_writer = (Get-FileHash (Join-Path $RepoRoot 'tests\performance\p0_result.ps1') -Algorithm SHA256).Hash
    env_helper = (Get-FileHash (Join-Path $RepoRoot 'tests\performance\p0_env.ps1') -Algorithm SHA256).Hash
}
$result['verdict'] = $(if ($script:finalRc -eq 0) { 'PASS' } else { 'FAIL' })
$result['exit_code'] = $script:finalRc          # planned exit decided by THIS script
$result['expected_exit'] = 0
$result['failure_stage'] = $(if ($script:exceptionMessage) { 'exception' } elseif ($probeFail) { 'sampling' } elseif ($script:finalRc) { 'final' } else { '' })
$result['reason_code'] = $(if ($script:exceptionMessage) { 'UNHANDLED_EXCEPTION' } elseif ($probeFail) { 'PROBE_FAILURE' } elseif ($script:finalRc) { 'CLEANUP_FAILURE' } else { 'OK' })
$result['reason_detail'] = if ($script:exceptionMessage) { $script:exceptionMessage } else { '' }
$result['samples'] = $script:sampleCount
$result['guard_active'] = $actualGuardActive
$result['guard_blocked_count'] = $actualGuardBlocked
$result['fallback_hits'] = $fallbackHitsField   # 'not_deployed' - never a fake 0
$result['owned_processes'] = [object[]]$script:ownedProcesses.ToArray()
$result['processes_recovered'] = $script:processesRecovered     # identity-recheck bound
$result['identity_recheck_passed'] = $script:identityRecheckPassed
$result['recovery_details'] = [object[]]$script:recoveryDetails.ToArray()
$result['port_released'] = $actualPortReleased
$result['evidence_path'] = $outFile
$result['temp_root'] = $root
# R4: ended_at = real window end (after recovery); result_built_at separate
if (-not $script:runWindowEnd) { $script:runWindowEnd = (Get-Date).ToString('o') }
$result['ended_at'] = $script:runWindowEnd
$result['result_built_at'] = (Get-Date).ToString('o')
$result['notes'] = 'S4/R4: started_at/ended_at are the real run window; result_built_at is when this JSON was assembled; processes_recovered bound to per-identity recheck (gone/still_alive_same_identity/pid_reused/query_failed; query_failed fails); port_released independent; planned exit recorded here - the OUTER RECORDER records the observed exit'
Write-RunResult $result $resultPath
Write-Host ("result written: {0}" -f $resultPath)
exit $script:finalRc


