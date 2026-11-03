# P0 measurement harness v3 (ASCII only, PS 5.1 safe)
# F2/F3/F4 remediation (see docs/reviews/native-desktop/P0-CODEX-remediation-final-review-2026-09-28.md):
#  F2: failures accumulated; ONE exit decision after finally; result.json carries
#      the actual exit code and failed stages; stdout markers are optional
#      observations only; mandatory readiness = /api/version 200 AND / == 200;
#      preview requires all 12 valid samples; owned-process identities recorded
#      before kill and rechecked afterwards; PNG validated on full signature +
#      IHDR + CRC32 + expected width.
#  F3: babeldoc cache staged from install home WITH per-file SHA256 integrity
#      check (missing/corrupt -> pre-start failure, never a silent download);
#      every child runs with tests/performance/p0_guard/sitecustomize.py on
#      PYTHONPATH: non-loopback connects are blocked and logged (loopback API
#      passes); blocked attempts are classified per phase (warmup-window vs
#      post-ready) and post-ready attempts fail the run.
#  F4: PDF2ZH_CONFIG_FILE explicitly isolated into the root; path-affecting
#      child env whitelisted (other PDF2ZH_*/BABELDOC_* overrides stripped);
#      parent PYTHONPATH/Git env saved and restored; dead -CleanRoot removed.
#
# Negative-test hooks (-FailInject, test-only, never default):
#   root404         stub server answers /api/version 200 and / 404
#   early-exit      backend process exits immediately
#   missing-cache   removes one staged cache file before validation
#   corrupt-cache   overwrites one staged cache file with garbage
#   cleanup-leftover injects a tagged python before the leftover recheck
#
# Exit codes: 0 all mandatory steps passed; 1 failure(s); 3 port conflict;
#             4 missing/corrupt prerequisite

param(
    [string]$PythonExe = '',
    [string]$EvidenceRoot = '',
    [ValidateSet('repo', 'installed')]
    [string]$SourceBackend = 'repo',
    [string]$InstallRoot = (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) '.local\runtime'),
    [string]$RepoRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent),
    [int]$Port = 7913,
    [int]$IdleSeconds = 300,
    [int]$StartupRuns = 3,
    [ValidateSet('', 'root404', 'early-exit', 'missing-cache', 'corrupt-cache', 'cleanup-leftover')]
    [string]$FailInject = '',
    [switch]$PathOnly, # pure local output-routing proof; never starts a backend
    [string]$OutDir = ''
)

. (Join-Path $PSScriptRoot 'p0_paths.ps1')
$EvidenceRoot = Resolve-P0EvidenceRoot $RepoRoot $EvidenceRoot

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http

if ($PathOnly) {
    $baseEv = if ($OutDir) { $OutDir } else { Join-Path $EvidenceRoot 'runs\baseline' }
    if (Test-Path -LiteralPath $baseEv) { Write-Host '[FAIL] output exists (refuse overwrite)'; exit 2 }
    New-Item -ItemType Directory -Path $baseEv -Force | Out-Null
    @{ mode = 'path-only-not-baseline'; requested_out_dir = $OutDir; resolved_base = $baseEv; run_dir = (Join-Path $baseEv ('run-v3-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))); pid = $PID } | ConvertTo-Json | Set-Content (Join-Path $baseEv 'path-proof.json') -Encoding UTF8
    exit 0
}

# ---------- parent env save/restore (F4) --------------------------------------
$savedPy = $env:PYTHONPATH
$savedGc = @($env:GIT_CONFIG_COUNT, $env:GIT_CONFIG_KEY_0, $env:GIT_CONFIG_VALUE_0)

# ---------- failure accumulation ----------------------------------------------
$script:Failures = New-Object System.Collections.Generic.List[string]
$script:unhandled = $null
function Fail([string]$step, [string]$why) {
    $script:Failures.Add("$step : $why") | Out-Null
    Write-Host ("[FAIL] {0} : {1}" -f $step, $why)
}
function Pass([string]$step, [string]$why) { Write-Host ("[PASS] {0} {1}" -f $step, $why) }

# ---------- paths & prerequisites ---------------------------------------------
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
if ($SourceBackend -eq 'repo') {
    $sourceDir = Join-Path $RepoRoot 'source'
    $webuiDir = Join-Path $RepoRoot 'webui'
    $scriptPy = Join-Path $RepoRoot 'start-webui.py'
} else {
    $sourceDir = $null
    $webuiDir = Join-Path $InstallRoot 'webui'
    $scriptPy = Join-Path $InstallRoot 'start-webui.py'
}
$pyBase = Join-Path $InstallRoot 'uv-python'
$sitePackages = Join-Path $InstallRoot 'uv-tools\pdf2zh-next\Lib\site-packages'
$cacheSrc = Join-Path $InstallRoot 'home\.cache\babeldoc'
$guardDir = Join-Path $RepoRoot 'tests\performance\p0_guard'

foreach ($p in @($InstallRoot, $sitePackages, $scriptPy, $webuiDir, $guardDir)) {
    if (-not ($p -and ([IO.Path]::IsPathRooted($p)) -and (Test-Path $p))) {
        Write-Host "[FAIL] prerequisite missing: $p"; exit 4
    }
}
if ($SourceBackend -eq 'repo' -and -not (Test-Path $sourceDir)) {
    Write-Host "[FAIL] repo source missing: $sourceDir"; exit 4
}
$python = Resolve-P0Python $InstallRoot $PythonExe
if (-not $python) { Write-Host '[FAIL] python.exe not found'; exit 4 }

# ---------- isolated root -------------------------------------------------------
$script:p0GuardSha = (Get-FileHash (Join-Path $guardDir 'sitecustomize.py') -Algorithm SHA256).Hash
$tempBase = [IO.Path]::GetFullPath($env:TEMP)
if (-not $tempBase.EndsWith('\')) { $tempBase += '\' }
$root = Join-Path $tempBase ("pdf2zh-p0-" + $stamp + "-" + $PID)
$home0 = Join-Path $root 'home'
$workDir = Join-Path $root 'work'
$logDir = Join-Path $root 'logs'
$guardLog = Join-Path $root 'guard.log'
$configFile = Join-Path $home0 '.config\pdf2zh\config.v3.toml'
foreach ($d in @($root, $home0, $workDir, $logDir, (Join-Path $home0 'Temp'), (Join-Path $home0 '.config\pdf2zh'))) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
}
Set-Content -Path $configFile -Value '' -Encoding ASCII   # isolated config (F4)

$owner = [ordered]@{
    script = 'p0_baseline.ps1 v3'; hostPid = $PID; created = (Get-Date).ToString('o')
    root = $root; sourceBackend = $SourceBackend; failInject = $FailInject
    purpose = 'P0 measurement isolation'
}
Set-Content -Path (Join-Path $root 'owner.json') -Value ($owner | ConvertTo-Json) -Encoding UTF8
Write-Host ("[root] {0}" -f $root)

# R4/B2: honor the -OutDir param when given (PS var names are case-insensitive,
# so the internal variable MUST have a different name than the param). The
# default targets THIS round's evidence root; the recorder passes a fresh
# -OutDir (created only by this entry, never pre-built by the recorder).
$baseEv = if ($OutDir) { $OutDir } else { Join-Path $EvidenceRoot 'runs\baseline' }
$runDir = Join-Path $baseEv ("run-v3-" + $stamp + $(if ($FailInject) { '-' + $FailInject }))
if ((Test-Path $runDir) -and (Get-ChildItem $runDir -ErrorAction SilentlyContinue)) {
    Write-Host ("[FAIL] run dir already exists and is non-empty (refuse overwrite): " + $runDir)
    exit 2
}
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

function Log([string]$msg) {
    $line = "[{0:HH:mm:ss.fff}] {1}" -f (Get-Date), $msg
    Write-Host $line
    Add-Content -Path (Join-Path $runDir 'harness.log') -Value $line -Encoding UTF8
}

# ---------- port pre-check -------------------------------------------------------
$l = [System.Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $Port)
try { $l.Start(); $l.Stop() } catch { Write-Host "[FAIL] port $Port already in use"; exit 3 }
Pass 'port-precheck' "127.0.0.1:$Port free"

# ---------- babeldoc cache staging + integrity (C1: authoritative) -----------
# C1: authoritative SHA3-256 verification against LOCKED package metadata
$dstCache = Join-Path $home0 '.cache\babeldoc'
if (-not (Test-Path $cacheSrc)) {
    Write-Host '[FAIL] babeldoc cache missing in install home; offline mode refuses download'
    exit 4
}
Log 'staging babeldoc cache into isolated home (read-only borrow)...'
robocopy $cacheSrc $dstCache /E /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { Write-Host ("[FAIL] robocopy rc=" + $LASTEXITCODE); exit 4 }

if ($FailInject -eq 'missing-cache') {
    $victim = Get-ChildItem $dstCache -Recurse -File | Sort-Object Length | Select-Object -First 1
    Remove-Item $victim.FullName -Force
    Log ("inject: removed staged cache file " + $victim.Name)
}
if ($FailInject -eq 'corrupt-cache') {
    $victim = Get-ChildItem $dstCache -Recurse -File | Sort-Object Length -Descending | Select-Object -First 1
    [IO.File]::WriteAllBytes($victim.FullName, [byte[]](0, 1, 2, 3))
    Log ("inject: corrupted staged cache file " + $victim.Name)
}

# C1: authoritative asset verification against locked babeldoc metadata
. (Join-Path $RepoRoot 'tests\performance\p0_asset_check.ps1')
Log 'verifying required assets against LOCKED babeldoc metadata (SHA3-256)...'
$assetOk = Invoke-AssetCheck -CacheDir $dstCache -InstallRoot $InstallRoot -IsolatedHome $home0 -PythonExe $python
if (-not $assetOk) {
    Write-Host '[FAIL] authoritative asset check: missing or corrupt assets; refusing to start backend'
    exit 4
}
Pass 'asset-integrity' 'all required assets verified against locked babeldoc SHA3-256'

# copy consistency check (retained; secondary to authoritative check)
Log 'verifying cache copy consistency (per-file SHA256, source vs staged copy)...'
$srcList = Get-ChildItem $cacheSrc -Recurse -File
$bad = 0; $missing = 0
foreach ($f in $srcList) {
    $rel = $f.FullName.Substring($cacheSrc.Length).TrimStart('\')
    $dst = Join-Path $dstCache $rel
    if (-not (Test-Path $dst)) { $missing++; continue }
    $hs = (Get-FileHash $f.FullName -Algorithm SHA256).Hash
    $hd = (Get-FileHash $dst -Algorithm SHA256).Hash
    if ($hs -ne $hd) { $bad++ }
}
$dstCount = (Get-ChildItem $dstCache -Recurse -File | Measure-Object).Count
if ($srcList.Count -ne $dstCount) {
    $bad += [math]::Abs($srcList.Count - $dstCount)
}
if ($missing -gt 0 -or $bad -gt 0) {
    Write-Host ("[FAIL] cache integrity: missing={0} mismatch={1} (offline mode: fix staging, never download)" -f $missing, $bad)
    exit 4
}
Pass 'cache-integrity' ("{0} files verified byte-identical" -f $srcList.Count)

# ---------- sample PDFs (self-made, inside root) ----------------------------------
# These owned directories may be absent after the long asset precheck. Ensure
# them at the point of use; do not infer why an earlier empty directory vanished.
foreach ($ownedDir in @($workDir, $logDir)) { New-Item -ItemType Directory -Path $ownedDir -Force | Out-Null }
$genPy = @'
import sys
import pymupdf
base = sys.argv[1]
doc = pymupdf.open()
for i in range(20):
    page = doc.new_page()
    page.insert_text((72, 72), f"Sample Document Page {i+1}", fontsize=16)
    for line in range(12):
        page.insert_text((72, 110 + line * 22),
            f"Paragraph {line+1} on page {i+1}: the quick brown fox jumps over the lazy dog.",
            fontsize=11)
doc.save(base + r"\p0-sample-20p.pdf")
doc.close()
doc = pymupdf.open()
page = doc.new_page()
page.insert_text((72, 72), "Baseline Translation Test Page", fontsize=16)
body = ("This one-page document is generated locally for offline measurement. "
        "It is not uploaded anywhere.")
page.insert_textbox(pymupdf.Rect(72, 100, 520, 400), body, fontsize=11)
doc.save(base + r"\p0-sample-1p.pdf")
doc.close()
print("pdfs-generated")
'@
$genFile = Join-Path $logDir 'gen_pdfs.py'
Set-Content -Path $genFile -Value $genPy -Encoding UTF8
# R2: sample generation runs in an ISOLATED per-child env block - no parent
# env mutation, no real-home inheritance; CWD is the isolated work dir
$genExit = Invoke-P0PythonFile -PythonExe $python -ScriptFile $genFile -ScriptArgs @($workDir) -IsolatedHome $home0 -PythonPath $sitePackages -GuardDir $guardDir -LogPrefix (Join-Path $logDir 'sample-generator') -TimeoutSeconds 120
if ($genExit -ne 0) { Write-Host ("[FAIL] sample generation child exit={0}" -f $genExit); exit 4 }
foreach ($s in @('p0-sample-20p.pdf', 'p0-sample-1p.pdf')) {
    if (-not (Test-Path (Join-Path $workDir $s))) { Write-Host "[FAIL] sample missing: $s"; exit 4 }
}
Pass 'sample-gen' 'self-made PDFs staged'

# ---------- HTTP / PNG helpers -----------------------------------------------------
# strict PNG validator shared with negative tests (C3): full signature + IHDR
# + CRC32 + expected width + REAL decodeability via PIL; single source
. (Join-Path $RepoRoot 'tests\performance\p0_guard\png_check.ps1')
Set-PngPythonExe $python (Join-Path $InstallRoot 'uv-tools\pdf2zh-next\Lib\site-packages') -IsolatedHome $home0

function New-LocalClient {
    $h = [System.Net.Http.HttpClientHandler]::new()
    $h.UseProxy = $false
    $c = [System.Net.Http.HttpClient]::new($h)
    $c.Timeout = [TimeSpan]::FromSeconds(60)
    return $c
}

function Upload-Pdf($client, $path, $name) {
    $bytes = [IO.File]::ReadAllBytes($path)
    $form = [System.Net.Http.MultipartFormDataContent]::new()
    $content = New-Object System.Net.Http.ByteArrayContent (, $bytes)
    $form.Add($content, 'file', $name)
    $resp = $client.PostAsync("http://127.0.0.1:$Port/api/files", $form).GetAwaiter().GetResult()
    $body = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    $form.Dispose()
    if (-not $resp.IsSuccessStatusCode) { throw "upload failed: $($resp.StatusCode) $body" }
    return ($body | ConvertFrom-Json)
}

# ---------- process tree helpers -----------------------------------------------------
function Get-TreePids([uint32]$rootPid) {
    $tree = [System.Collections.Generic.HashSet[uint32]]::new()
    [void]$tree.Add($rootPid)
    $map = @{}
    foreach ($p in (Get-CimInstance Win32_Process -Filter "Name = 'python.exe'" -ErrorAction SilentlyContinue)) {
        $map[[uint32]$p.ProcessId] = [uint32]$p.ParentProcessId
    }
    $changed = $true
    while ($changed) {
        $changed = $false
        foreach ($procId in $map.Keys) {
            if (-not $tree.Contains($procId) -and $tree.Contains($map[$procId])) {
                [void]$tree.Add($procId); $changed = $true
            }
        }
    }
    return ,$tree
}

function Measure-Tree([uint32]$rootPid) {
    $tree = Get-TreePids $rootPid
    $cpu = 0.0; $priv = 0.0; $ws = 0.0; $threads = 0; $handles = 0; $count = 0
    foreach ($proc in (Get-Process -ErrorAction SilentlyContinue)) {
        if (-not $tree.Contains([uint32]$proc.Id)) { continue }
        try {
            $cpu += $proc.TotalProcessorTime.TotalSeconds
            $priv += $proc.PrivateMemorySize64
            $ws += $proc.WorkingSet64
            $threads += $proc.Threads.Count
            $handles += $proc.HandleCount
            $count += 1
        } catch { }
    }
    return [pscustomobject]@{
        cpuSeconds = [math]::Round($cpu, 2); privateMB = [math]::Round($priv / 1MB, 1)
        workingSetMB = [math]::Round($ws / 1MB, 1); threads = $threads
        handles = $handles; processes = $count
    }
}

$script:rootPid = 0
$script:client = $null

# F2: record owned-process identities before termination; verify afterwards
function Get-TreeIdentity([uint32]$rootPid) {
    $tree = Get-TreePids $rootPid
    $rows = @()
    foreach ($proc in (Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)) {
        if (-not $tree.Contains([uint32]$proc.ProcessId)) { continue }
        $rows += [pscustomobject]@{ pid = $proc.ProcessId; name = $proc.Name; created = $proc.CreationDate }
    }
    return $rows
}
function Test-IdentitiesGone($identities) {
    foreach ($idn in $identities) {
        $p = Get-Process -Id $idn.pid -ErrorAction SilentlyContinue
        if (-not $p) { continue }
        # pid alive: same process only if creation time matches recorded one
        $cim = Get-CimInstance Win32_Process -Filter ("ProcessId = " + $idn.pid) -ErrorAction SilentlyContinue
        if ($cim -and $cim.CreationDate -eq $idn.created) { return $false }
    }
    return $true
}

function Stop-Backend {
    $identities = $null
    if ($script:rootPid -gt 0) {
        $identities = Get-TreeIdentity ([uint32]$script:rootPid)
        try { taskkill /PID $script:rootPid /T /F 2>$null | Out-Null } catch { }
        Start-Sleep -Milliseconds 800
        if (-not (Test-IdentitiesGone $identities)) {
            Fail 'backend-stop' 'owned processes survived termination (identity recheck)'
        } else {
            Pass 'backend-stop' ("owned tree fully stopped (pids recorded: " + (($identities | ForEach-Object { $_.pid }) -join ',') + ")")
        }
        $script:rootPid = 0
    }
    if ($script:client) { $script:client.Dispose(); $script:client = $null }
    $conn = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    if ($conn) {
        Fail 'port-release' ("port {0} still listening (pid {1})" -f $Port, ($conn | Select-Object -First 1).OwningProcess)
    }
}

function Test-BackendOwnership {
    $conn = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $conn) { return $false }
    $tree = Get-TreePids ([uint32]$script:rootPid)
    return $tree.Contains([uint32]$conn.OwningProcess)
}

# ---------- child env builder (F3 guard + F4 whitelist) ------------------------------
function Set-ChildEnv($pinfo) {
    $pinfo.EnvironmentVariables['PDF2ZH_HOME'] = $home0
    $pinfo.EnvironmentVariables['PDF2ZH_CONFIG_FILE'] = $configFile          # F4
    $pinfo.EnvironmentVariables['PDF2ZH_WEBUI_DIR'] = $webuiDir
    $pinfo.EnvironmentVariables['HOME'] = $home0
    $pinfo.EnvironmentVariables['USERPROFILE'] = $home0
    $pinfo.EnvironmentVariables['APPDATA'] = (Join-Path $home0 'AppData\Roaming')
    $pinfo.EnvironmentVariables['LOCALAPPDATA'] = (Join-Path $home0 'AppData\Local')
    $pinfo.EnvironmentVariables['TEMP'] = (Join-Path $home0 'Temp')
    $pinfo.EnvironmentVariables['TMP'] = (Join-Path $home0 'Temp')
    $pinfo.EnvironmentVariables['PYTHONUTF8'] = '1'
    if ($SourceBackend -eq 'repo') {
        $pinfo.EnvironmentVariables['PYTHONPATH'] = $guardDir + ';' + $sourceDir + ';' + $sitePackages
    } else {
        $pinfo.EnvironmentVariables['PYTHONPATH'] = $guardDir + ';' + $sitePackages
    }
    $pinfo.EnvironmentVariables['PDF2ZH_GUARD_LOG'] = $guardLog
    $pinfo.EnvironmentVariables['PDF2ZH_GUARD_DIR'] = $guardDir
    $pinfo.EnvironmentVariables['PDF2ZH_RUN_ID'] = "baseline-$run-$stamp"
    # S1: hash binding - the entry gate refuses to start if the loaded guard
    # does not match the hash recorded by this harness (plain script variable,
    # never leaked into the parent/process environment)
    $pinfo.EnvironmentVariables['PDF2ZH_GUARD_SHA256'] = $script:p0GuardSha
    $pinfo.EnvironmentVariables['NO_PROXY'] = '127.0.0.1,localhost'
    $pinfo.EnvironmentVariables['no_proxy'] = '127.0.0.1,localhost'
    # F3/G2: strip proxy vars - a loopback proxy (e.g. 127.0.0.1:11178) could
    # tunnel outbound traffic past the socket guard
    $strip = @()
    foreach ($k in $pinfo.EnvironmentVariables.Keys) {
        if (($k -like 'PDF2ZH_*' -or $k -like 'BABELDOC_*' -or $k -like '*_PROXY') -and
            $k -notin @('PDF2ZH_HOME','PDF2ZH_CONFIG_FILE','PDF2ZH_WEBUI_DIR','PDF2ZH_GUARD_LOG','PDF2ZH_GUARD_DIR','PDF2ZH_RUN_ID','PDF2ZH_GUARD_SHA256','PDF2ZH_TARGET_SCRIPT','PDF2ZH_TARGET_ARGS','BABELDOC_ASSETS_UPSTREAM','NO_PROXY','no_proxy')) {
            $strip += $k
        }
    }
    foreach ($k in $strip) { $pinfo.EnvironmentVariables.Remove($k) | Out-Null }
}

# ---------- main flow ----------------------------------------------------------------
$startupRows = [System.Collections.Generic.List[object]]::new()
$script:plannedExit = 0
try {
    for ($run = 1; $run -le $StartupRuns; $run++) {
        $stdout = Join-Path $logDir "startup-run$run.log"
        $pinfo = [System.Diagnostics.ProcessStartInfo]::new()
        $pinfo.FileName = "$env:ComSpec"
        if ($FailInject -eq 'root404') {
            # controlled stub: /api/version -> 200, / -> 404 (same readiness loop)
            $stubFile = Join-Path $logDir 'stub404.py'
            @'
import http.server
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        code = 404 if self.path == "/" else 200
        self.send_response(code)
        self.end_headers()
    def log_message(self, *a):
        pass
http.server.HTTPServer(("127.0.0.1", __PORT__), H).serve_forever()
'@ -replace '__PORT__', "$Port" | Set-Content -Path $stubFile -Encoding ASCII
            $pinfo.Arguments = '/c ""' + $python + '" -u "' + $stubFile + '" > "' + $stdout + '" 2>&1"'
        } elseif ($FailInject -eq 'early-exit') {
            $pinfo.Arguments = '/c exit 5'
        } else {
            # S1: use entry_wrapper.py (runs entry_gate before target script)
            $entryWrapper = Join-Path $RepoRoot 'tests\performance\p0_guard\entry_wrapper.py'
            $pinfo.Arguments = '/c ""' + $python + '" -u "' + $entryWrapper + '" > "' + $stdout + '" 2>&1"'
            $pinfo.EnvironmentVariables['PDF2ZH_TARGET_SCRIPT'] = $scriptPy
            $pinfo.EnvironmentVariables['PDF2ZH_TARGET_ARGS'] = "--server-port $Port"
        }
        $pinfo.WorkingDirectory = $workDir
        $pinfo.UseShellExecute = $false
        $pinfo.CreateNoWindow = $true
        Set-ChildEnv $pinfo

        $proc = [System.Diagnostics.Process]::new()
        $proc.StartInfo = $pinfo
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        [void]$proc.Start()
        $script:rootPid = $proc.Id
        $injectLabel = $FailInject
        if (-not $injectLabel) { $injectLabel = 'none' }
        Log ("run {0} started (rootPid {1}) inject={2}" -f $run, $proc.Id, $injectLabel)

        # phase marker for net-guard classification (warmup window starts now)
        Add-Content -Path $guardLog -Value ("PHASE backend-start run$run " + $sw.Elapsed.TotalSeconds) -Encoding UTF8

        $tLogReady = $null; $tStartupComplete = $null; $tApi = $null; $tUi = $null
        $deadlineMs = if ($FailInject) { 30000 } else { 6 * 60 * 1000 }
        $client = New-LocalClient
        $script:client = $client
        # mandatory readiness = api200 AND root200; stdout markers are optional
        # observations recorded but never gate the loop (F2)
        while ($sw.ElapsedMilliseconds -lt $deadlineMs) {
            if ($proc.HasExited) { break }
            if (-not $tLogReady -and (Test-Path $stdout) -and (Select-String -Path $stdout -Pattern 'WebUI ready:' -Quiet)) { $tLogReady = $sw.ElapsedMilliseconds }
            if (-not $tStartupComplete -and (Test-Path $stdout) -and (Select-String -Path $stdout -Pattern 'Application startup complete' -Quiet)) { $tStartupComplete = $sw.ElapsedMilliseconds }
            if (-not $tApi) {
                try {
                    $r = $client.GetAsync("http://127.0.0.1:$Port/api/version").GetAwaiter().GetResult()
                    if ([int]$r.StatusCode -eq 200) { $tApi = $sw.ElapsedMilliseconds }
                } catch { }
            }
            if (-not $tUi) {
                try {
                    $r = $client.GetAsync("http://127.0.0.1:$Port/").GetAwaiter().GetResult()
                    if ([int]$r.StatusCode -eq 200) { $tUi = $sw.ElapsedMilliseconds }
                } catch { }
            }
            if ($tApi -and $tUi) { break }
            Start-Sleep -Milliseconds 50
        }

        if ($proc.HasExited) {
            Fail ("startup-$run") ("backend process exited early (code " + $proc.ExitCode + ")")
            Stop-Backend
            continue
        }
        if (-not (Test-BackendOwnership)) {
            Fail ("startup-$run") 'port listener is not owned by our process tree'
            Stop-Backend
            continue
        }
        if (-not $tApi) {
            Fail ("startup-$run") 'mandatory readiness failed: /api/version never returned 200 within deadline'
            Stop-Backend
            continue
        }
        if (-not $tUi) {
            # F2: api 200 but root page never 200 (e.g. 404) is a mandatory failure
            Fail ("startup-$run") 'mandatory readiness failed: root page did not return 200 (api was 200)'
            Stop-Backend
            continue
        }

        # phase marker: warmup/startup window ends at apiReady
        Add-Content -Path $guardLog -Value ("PHASE ready run$run " + $sw.Elapsed.TotalSeconds) -Encoding UTF8

        $row = [ordered]@{
            run = $run; rootPid = $proc.Id; backend = $SourceBackend
            logReadyObservedMs = $tLogReady; startupCompleteObservedMs = $tStartupComplete
            apiReadyMs = $tApi; root200Ms = $tUi
            exitedEarly = $proc.HasExited
        }
        $startupRows.Add([pscustomobject]$row)
        Log ("startup run {0}: {1}" -f $run, ($row | ConvertTo-Json -Compress))

        if ($run -eq 1 -and -not $FailInject) {
            # ---- idle sampling ----
            $idleCsv = Join-Path $runDir 'idle-5min.csv'
            't_sec,cpuSeconds,privateMB,workingSetMB,threads,handles,processes' | Set-Content -Path $idleCsv -Encoding ASCII
            $idleSw = [System.Diagnostics.Stopwatch]::StartNew()
            $cpuStart = (Measure-Tree ([uint32]$script:rootPid)).cpuSeconds
            while ($idleSw.ElapsedMilliseconds -lt ($IdleSeconds * 1000)) {
                Start-Sleep -Seconds 5
                $m = Measure-Tree ([uint32]$script:rootPid)
                Add-Content -Path $idleCsv -Value ("{0:N1},{1},{2},{3},{4},{5},{6}" -f ($idleSw.Elapsed.TotalSeconds), $m.cpuSeconds, $m.privateMB, $m.workingSetMB, $m.threads, $m.handles, $m.processes) -Encoding ASCII
            }
            $mEnd = Measure-Tree ([uint32]$script:rootPid)
            $wall = $idleSw.Elapsed.TotalSeconds
            $cpuDelta = $mEnd.cpuSeconds - $cpuStart
            $logical = [Environment]::ProcessorCount
            $norm = [math]::Round($cpuDelta / ($wall * $logical) * 100, 4)
            [pscustomobject]@{
                metric = 'idle'; backend = $SourceBackend
                wallSec = [math]::Round($wall, 1); cpuSecondsDelta = [math]::Round($cpuDelta, 2)
                normalizedCpuPercent = $norm; logicalProcessors = $logical
                privateMBEnd = $mEnd.privateMB; workingSetMBEnd = $mEnd.workingSetMB
                threadsEnd = $mEnd.threads; handlesEnd = $mEnd.handles; processesEnd = $mEnd.processes
            } | ConvertTo-Json | Set-Content (Join-Path $runDir 'idle-summary.json') -Encoding UTF8
            Log ("idle: wall={0:N1}s cpuDelta={1:N2}s norm={2}% privEnd={3}MB wsEnd={4}MB" -f $wall, $cpuDelta, $norm, $mEnd.privateMB, $mEnd.workingSetMB)

            # ---- preview (12 renders, strict PNG validation) ----
            try {
                $up = Upload-Pdf $client (Join-Path $workDir 'p0-sample-20p.pdf') 'p0-sample-20p.pdf'
                $prevCsv = Join-Path $runDir 'preview-latency.csv'
                'request,pixelWidth,ms,contentKB,pngWidth,pngHeight' | Set-Content -Path $prevCsv -Encoding ASCII
                $times = @()
                for ($i = 1; $i -le 12; $i++) {
                    $page = (($i - 1) % 4) + 1
                    $rsw = [System.Diagnostics.Stopwatch]::StartNew()
                    $r = $client.GetAsync("http://127.0.0.1:$Port/api/files/$($up.file_id)/preview?page=$page&width=900").GetAwaiter().GetResult()
                    $bytesResp = $r.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
                    $rsw.Stop()
                    $ct = $r.Content.Headers.ContentType.MediaType
                    $wRef = 0; $hRef = 0; $whyRef = ''
                    $ok = Test-PngStrict $bytesResp 900 ([ref]$wRef) ([ref]$hRef) ([ref]$whyRef)
                    if ([int]$r.StatusCode -ne 200 -or $ct -ne 'image/png' -or -not $ok) {
                        Fail 'preview' ("request {0}: status={1} ct={2} pngCheck={3}" -f $i, $r.StatusCode, $ct, $whyRef)
                        break
                    }
                    $times += $rsw.Elapsed.TotalMilliseconds
                    Add-Content -Path $prevCsv -Value ("{0},900,{1:N1},{2},{3},{4}" -f $i, $rsw.Elapsed.TotalMilliseconds, [math]::Round($bytesResp.Length / 1KB, 1), $wRef, $hRef) -Encoding ASCII
                }
                if ($times.Count -eq 12) {
                    $sorted = $times | Sort-Object
                    $mid = [int]($sorted.Count / 2)
                    $median = if ($sorted.Count % 2 -eq 1) { $sorted[$mid] } else { ($sorted[$mid - 1] + $sorted[$mid]) / 2.0 }
                    $p95 = $sorted[[math]::Min($sorted.Count - 1, [math]::Ceiling(0.95 * $sorted.Count) - 1)]
                    [pscustomobject]@{
                        metric = 'preview_render'; backend = $SourceBackend; n = $times.Count
                        meanMs = [math]::Round(($times | Measure-Object -Average).Average, 1)
                        medianMs = [math]::Round($median, 1); p95Ms = [math]::Round($p95, 1)
                        maxMs = [math]::Round(($times | Measure-Object -Maximum).Maximum, 1)
                        widthPx = 900; pagesCycled = '1-4'
                        note = 'nearest-rank p95; median = mean of two middle values; server-side render only, not UI page-turn latency'
                    } | ConvertTo-Json | Set-Content (Join-Path $runDir 'preview-summary.json') -Encoding UTF8
                    Pass 'preview' ("n=12 mean={0:N0}ms median={1:N0}ms p95={2:N0}ms" -f ($times | Measure-Object -Average).Average, $median, $p95)
                } elseif ($script:Failures.Count -eq 0) {
                    Fail 'preview' ("only {0}/12 valid samples" -f $times.Count)
                }
            } catch {
                Fail 'preview' $_.Exception.Message
            }
        }

        if ($FailInject -eq 'cleanup-leftover' -and $run -eq 1) {
            # inject a tagged python that is NOT part of the owned tree, then
            # verify the identity-recheck path flags it; reaped by this test
            $dummy = [System.Diagnostics.Process]::new()
            $dp = [System.Diagnostics.ProcessStartInfo]::new()
            $dp.FileName = $python
            $dp.Arguments = '-c "import time; time.sleep(20)"'
            $dp.UseShellExecute = $false; $dp.CreateNoWindow = $true
            $dummy.StartInfo = $dp
            [void]$dummy.Start()
            $fakeId = @([pscustomobject]@{ pid = $dummy.Id; name = 'python.exe'; created = (Get-CimInstance Win32_Process -Filter ("ProcessId = " + $dummy.Id)).CreationDate })
            if (-not (Test-IdentitiesGone $fakeId)) {
                Fail 'cleanup-leftover' 'injected live process detected by identity recheck (expected for this scenario)'
            } else {
                Fail 'cleanup-leftover' 'identity recheck FAILED to detect the injected live process'
            }
            try { taskkill /PID $dummy.Id /T /F 2>$null | Out-Null } catch { }
        }

        Log 'translation: never submitted (offline requirement, note only)'
        Stop-Backend
        Start-Sleep -Seconds 2
    }
} catch {
    # G1: an uncaught exception must become a recorded failure, never exit 0
    $script:unhandled = $_.Exception.Message
    Fail 'unhandled-exception' $script:unhandled
} finally {
    Stop-Backend
    $startupRows | ConvertTo-Json | Set-Content (Join-Path $runDir 'startup-summary.json') -Encoding UTF8
    Get-ChildItem $logDir -Filter 'startup-run*.log' -ErrorAction SilentlyContinue | ForEach-Object {
        Copy-Item $_.FullName (Join-Path $runDir ('backend-' + $_.Name)) -Force
    }
    Copy-Item (Join-Path $logDir 'gen_pdfs.py') (Join-Path $runDir 'gen_pdfs.py') -Force -ErrorAction SilentlyContinue
    if (Test-Path $guardLog) { Copy-Item $guardLog (Join-Path $runDir 'guard.log') -Force }

    # net-guard classification: B2 - guard.log must exist AND contain
    # GUARD_ACTIVE; otherwise the guard never loaded and the run is INVALID
    if (-not (Test-Path $guardLog)) {
        Fail 'net-guard' 'guard.log missing: guard never loaded; run invalid (B2)'
    } elseif (-not (Select-String -Path $guardLog -Pattern 'GUARD_ACTIVE' -Quiet)) {
        Fail 'net-guard' 'guard.log exists but GUARD_ACTIVE not found: guard failed to load (B2)'
    } else {
        $phase = 'warmup'; $warmupBlocked = 0; $postBlocked = @()
        foreach ($line in (Get-Content $guardLog -ErrorAction SilentlyContinue)) {
            if ($line -like 'PHASE ready*') { $phase = 'ready' }
            elseif ($line -like 'PHASE backend-start*') { if ($phase -eq 'ready') { $phase = 'warmup' } }
            elseif ($line -like '* BLOCKED *') {
                if ($phase -eq 'ready') { $postBlocked += $line } else { $warmupBlocked++ }
            }
        }
        "warmup-window blocked outbound attempts: $warmupBlocked (expected: warmup may probe; cache was complete so no downloads occurred)" |
            Set-Content (Join-Path $runDir 'net-guard-summary.txt') -Encoding UTF8
        if ($postBlocked.Count -gt 0) {
            Fail 'net-guard' ("post-ready outbound attempts blocked: " + $postBlocked.Count)
            $postBlocked | Add-Content (Join-Path $runDir 'net-guard-summary.txt') -Encoding UTF8
        }
    }

    $script:plannedExit = 1
    if ($script:Failures.Count -eq 0 -and -not $script:unhandled) { $script:plannedExit = 0 }
    [pscustomobject]@{
        exitCode = $script:plannedExit
        failures = $script:Failures
        unhandledException = $script:unhandled
        runDir = $runDir; tempRoot = $root; backend = $SourceBackend; failInject = $FailInject
        note = 'single exit decision made here after finally cleanup; translation never submitted (offline)'
    } | ConvertTo-Json | Set-Content (Join-Path $runDir 'result.json') -Encoding UTF8
    Log ("DONE failures={0} evidence={1}" -f $script:Failures.Count, $runDir)
    Log ("temp root preserved (not auto-deleted): {0}" -f $root)
}

# restore parent env (F4)
if ($null -ne $savedPy) { $env:PYTHONPATH = $savedPy } else { Remove-Item Env:PYTHONPATH -ErrorAction SilentlyContinue }
$env:GIT_CONFIG_COUNT = $savedGc[0]; $env:GIT_CONFIG_KEY_0 = $savedGc[1]; $env:GIT_CONFIG_VALUE_0 = $savedGc[2]

exit $script:plannedExit


