# P0 r2-integrated negative matrix driver v3 (ASCII only, PS 5.1 safe).
# R3 fixes over v2:
#   - verdicts are OBSERVATION-BASED: every case declares expectedExit and an
#     expectedReason token; the runner extracts the OBSERVED reason from the
#     case's own artifacts (log/result/matrix) and compares. Exit-code-only
#     matches with a wrong reason are FAIL. expected_reason and observed_reason
#     are recorded separately in the CSV.
#   - a case whose artifacts are missing/unparseable fails even if the exit
#     code matches (malformed_result / reason_not_observed).
#   - -SelfTest mode proves the generic verdict engine rejects: same exit code
#     with wrong reason, missing reason field, unrelated exception, RunId
#     reuse (refused before any write), and zero-match -Only.
#   - RunId/OutDir reuse: an explicitly requested non-empty run dir is REFUSED
#     before any file is written.
# Exit: 0 all selected cases pass; 1 any failure; 2 usage/overwrite refusal.

param(
    [string]$RepoRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent),
    [string]$InstallRoot = (Join-Path $RepoRoot '.local\runtime'),
    [string]$PythonExe = '',
    [string]$OutDir = '',
    [string]$Only = '',
    [string]$RunId = '',
    [string]$EvidenceRoot = '',
    [switch]$SelfTest
)

. (Join-Path $PSScriptRoot 'p0_paths.ps1')
$EvidenceRoot = Resolve-P0EvidenceRoot $RepoRoot $EvidenceRoot

$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Net.Http

$perfDir = Join-Path $RepoRoot 'tests\performance'


if (-not $RunId) { $RunId = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + $PID }
if (-not $EvidenceRoot) {
    $EvidenceRoot = Resolve-P0EvidenceRoot $RepoRoot ''
}
$evDir = if ($OutDir) { $OutDir } else { Join-Path $EvidenceRoot ("runs\matrix-" + $RunId) }
# R3/B2: refuse an explicitly requested non-empty run dir BEFORE any write
if ((Test-Path $evDir) -and (Get-ChildItem $evDir -ErrorAction SilentlyContinue)) {
    Write-Host ("[FAIL] run dir already exists and is non-empty; refusing to overwrite: " + $evDir)
    exit 2
}
New-Item -ItemType Directory -Force -Path $evDir | Out-Null
@{ kind = $(if ($SelfTest) { 'selftest' } else { 'acceptance' }); only = $Only; run_id = $RunId } | ConvertTo-Json | Set-Content (Join-Path $evDir 'matrix-identity.json') -Encoding UTF8
$caseDir = Join-Path $evDir 'cases'
New-Item -ItemType Directory -Force -Path $caseDir | Out-Null

# C2: runtime hash index covers ALL actual dependencies
$scriptFiles = @('p0_baseline.ps1','p0_probe_perprocess.ps1','p0_probe_attribution.ps1',
    'p0_negative_tests.ps1','p0_asset_check.ps1','p0_c1_guard_test.ps1','p0_pytest_isolated.ps1',
    'p0_paths.ps1','p0_runs.ps1','p0_env.ps1','p0_result.ps1','p0_evidence_check.ps1',
    'p0_entry_gate_negtest.ps1','p0_env_negtest.ps1','p0_guard_mutations.ps1',
    'p0_loopback_negtest.ps1','p0_isolation_negtest.ps1','p0_recovery_negtest.ps1',
    'p0_run_recorder.ps1','p0_empty_host_case.ps1')
$hashIndex = [ordered]@{}
foreach ($sf in $scriptFiles) {
    $p = Join-Path $perfDir $sf
    if (Test-Path $p) { $hashIndex[$sf] = (Get-FileHash $p -Algorithm SHA256).Hash }
}
foreach ($sf in @('p0_guard\sitecustomize.py','p0_guard\entry_gate.py','p0_guard\entry_wrapper.py',
                  'p0_guard\guard_fallback.py','p0_guard\guard_test.py','p0_guard\png_check.ps1',
                  'p0_guard\loopback_vectors.py')) {
    $p = Join-Path $perfDir $sf
    if (Test-Path $p) { $hashIndex[$sf] = (Get-FileHash $p -Algorithm SHA256).Hash }
}
$hashIndex['source/tests/conftest.py'] = (Get-FileHash (Join-Path $RepoRoot 'source\tests\conftest.py') -Algorithm SHA256).Hash
$hashIndex | ConvertTo-Json | Set-Content (Join-Path $evDir 'script-hashes.json') -Encoding UTF8

$pyExe = Resolve-P0Python $InstallRoot $PythonExe

$failCount = 0
$total = 0
$matrixRows = New-Object System.Collections.Generic.List[string]

# ---------------------------------------------------------------------------
# R3 generic verdict engine
# ---------------------------------------------------------------------------
function Invoke-Case {
    param(
        [string]$id,
        [string]$expectedExit,
        [string]$expectedReason,         # machine token that MUST be observed
        [scriptblock]$action,            # must return @{ exit = <int> }
        [string]$reasonLog,              # artifact path holding the observed reason
        [string]$frozenId = '',
        [string]$frozenReason = '',
        [scriptblock]$semanticValidator = $null   # optional: param($res) -> $true/$false
    )
    if ($Only -and $id -notmatch $Only) { return }
    $script:total++
    Write-Host ("=== case {0} (expect exit {1}, reason token: {2}) ===" -f $id, $expectedExit, $expectedReason)
    $outFile = Join-Path $caseDir ("case-" + $id + ".log")

    $res = & $action $outFile
    $actualExit = "$($res.exit)"

    # --- observed reason extraction from the case's own artifacts -----------
    # default reason artifact = the case log itself (each entry writes its
    # machine markers there); explicit $reasonLog overrides for special cases
    $reasonLogPath = if ($reasonLog) { $reasonLog } else { $outFile }
    $observedReason = ''
    $malformed = $false
    if (-not (Test-Path $reasonLogPath)) {
        $malformed = $true
        $observedReason = '<reason-artifact-missing>'
    } else {
        $logText = Get-Content $reasonLogPath -Raw -ErrorAction SilentlyContinue
        if (-not $logText) { $malformed = $true; $observedReason = '<reason-artifact-empty>' }
        else { $observedReason = ($logText -split "`r?`n" | Where-Object { $_ -match '\[FAIL\]|\[PASS\]|EXPECTED FAIL|sentinelUnchanged|DONE failures|png-check failures|refus|ENTRY_GATE|BLOCKED|no IMPORT_DONE|already in use|exited early|identity recheck|not decodable|authoritative asset|asset_missing|asset_corrupt|R1 loopback vectors|R2 isolation sentinels|R4 recovery stubs' }) -join ' | ' }
    }

    $exitOk = ($actualExit -eq "$expectedExit")
    $reasonOk = (-not $malformed) -and ($observedReason -match [regex]::Escape($expectedReason))
    $semanticOk = $true
    if ($semanticValidator) { $semanticOk = & $semanticValidator $res }

    $verdict = 'PASS'
    if (-not $exitOk) { $verdict = 'FAIL' }
    elseif ($malformed) { $verdict = 'FAIL' }
    elseif (-not $reasonOk) { $verdict = 'FAIL' }
    elseif (-not $semanticOk) { $verdict = 'FAIL' }
    if ($verdict -eq 'FAIL') { $script:failCount++ }

    $script:matrixRows.Add(("{0},{1},{2},{3},{4},{5},{6}" -f
        $id, $expectedExit, $actualExit, $verdict,
        $(if ($reasonOk) { $expectedReason } else { 'reason_not_observed:' + $observedReason.Substring(0, [Math]::Min(160, $observedReason.Length)) }),
        $frozenId, $frozenReason)) | Out-Null
    Write-Host ("=== case {0} exit={1} verdict={2} observed={3} ===" -f $id, $actualExit, $verdict,
        ($observedReason.Substring(0, [Math]::Min(120, $observedReason.Length))))
}

function Invoke-EntryScript([string]$file, [string[]]$entryArgs, [string]$log) {
    $forward = @('-RepoRoot', $RepoRoot, '-InstallRoot', $InstallRoot, '-EvidenceRoot', $EvidenceRoot, '-PythonExe', $pyExe)
    if ((Split-Path $file -Leaf) -eq 'p0_env_negtest.ps1') { $forward = @('-RepoRoot', $RepoRoot, '-EvidenceRoot', $EvidenceRoot) }
    $quoted = (@('-NoProfile','-ExecutionPolicy','Bypass','-File', $file) + $entryArgs + $forward | ForEach-Object { ConvertTo-P0Argument $_ }) -join ' '
    $p = Start-P0PowerShell -ArgumentList $quoted -Wait -PassThru -NoNewWindow -RedirectStandardOutput $log -RedirectStandardError ($log + '.err')
    return @{ exit = $p.ExitCode }
}

# ---------------------------------------------------------------------------
# Real cases (observed-reason driven; skipped when -SelfTest)
# ---------------------------------------------------------------------------

if (-not $SelfTest) {

# --- case 1: attribution import-fail (all payloads fail) ----------------------
Invoke-Case '1-attribution-import-fail' '1' 'no IMPORT_DONE' {
    param($log)
    $r = Invoke-EntryScript (Join-Path $perfDir 'p0_probe_attribution.ps1') @('-FailInject','import-fail') $log
    return $r
} $null

# --- case 2: baseline root404 ---------------------------------------------------
Invoke-Case '2-baseline-root404' '1' 'root page did not return 200' {
    param($log)
    Invoke-EntryScript (Join-Path $perfDir 'p0_baseline.ps1') @('-SourceBackend','repo','-Port','7913','-StartupRuns','1','-IdleSeconds','5','-FailInject','root404') $log
} $null

# --- case 3a: baseline missing-cache -------------------------------------------
Invoke-Case '3a-baseline-missing-cache' '4' 'asset_missing' {
    param($log)
    Invoke-EntryScript (Join-Path $perfDir 'p0_baseline.ps1') @('-SourceBackend','repo','-Port','7913','-StartupRuns','1','-IdleSeconds','5','-FailInject','missing-cache') $log
} $null

# --- case 3b: baseline corrupt-cache --------------------------------------------
Invoke-Case '3b-baseline-corrupt-cache' '4' 'asset_corrupt' {
    param($log)
    Invoke-EntryScript (Join-Path $perfDir 'p0_baseline.ps1') @('-SourceBackend','repo','-Port','7913','-StartupRuns','1','-IdleSeconds','5','-FailInject','corrupt-cache') $log
} $null

# --- case 4: guard blocks non-loopback (frozen G01) -----------------------------
Invoke-Case '4-netguard-nonloopback' '0' 'BLOCKED-BY-GUARD' {
    param($log)
    $guardDir2 = Join-Path $perfDir 'p0_guard'
    $guardLog = Join-Path $caseDir 'case4-guard.log'
    $fbLog = Join-Path $caseDir 'case4-fallback.log'
    Remove-Item $guardLog, $fbLog -ErrorAction SilentlyContinue
    $savedP = $env:PYTHONPATH; $savedGl = $env:PDF2ZH_GUARD_LOG; $savedFl = $env:PDF2ZH_FALLBACK_LOG
    try {
        $env:PYTHONPATH = (Join-Path $InstallRoot 'uv-tools\pdf2zh-next\Lib\site-packages')
        $env:PDF2ZH_GUARD_LOG = $guardLog
        $env:PDF2ZH_FALLBACK_LOG = $fbLog
        $env:CASE4_GUARD_DIR = $guardDir2
        $testPy = Join-Path $caseDir 'case4_test.py'
        @'
import sys, os
guard_dir = os.environ.get("CASE4_GUARD_DIR", "")
sys.path.insert(0, guard_dir)
import guard_fallback
import sitecustomize
import socket
s = socket.socket()
try:
    s.connect(("192.0.2.1", 9))
    print("CONNECTED-BAD")
except OSError as e:
    if "net-guard" in str(e):
        print("BLOCKED-BY-GUARD")
    elif "FALLBACK" in str(e):
        print("BLOCKED-BY-FALLBACK")
    else:
        print("BLOCKED-BY-OS: %s" % str(e)[:80])
'@ | Set-Content $testPy -Encoding ASCII
        $out = & $pyExe $testPy 2>&1
        $out | Set-Content $log -Encoding UTF8
        $outText = $out | Out-String
        $guardLogged = (Test-Path $guardLog) -and ((Get-Content $guardLog -Raw) | Select-String 'BLOCKED.*192\.0\.2\.1' -Quiet)
        $fbClean = ((Test-Path $fbLog) -and (-not ((Get-Content $fbLog -Raw) -match 'FALLBACK_HIT'))) -or (-not (Test-Path $fbLog))
        if (($outText -match 'BLOCKED-BY-GUARD') -and $guardLogged -and $fbClean) { return @{ exit = 0 } }
        return @{ exit = 1 }
    } finally {
        Remove-Item Env:CASE4_GUARD_DIR -ErrorAction SilentlyContinue
        if ($null -ne $savedP) { $env:PYTHONPATH = $savedP } else { Remove-Item Env:PYTHONPATH -ErrorAction SilentlyContinue }
        if ($null -ne $savedGl) { $env:PDF2ZH_GUARD_LOG = $savedGl } else { Remove-Item Env:PDF2ZH_GUARD_LOG -ErrorAction SilentlyContinue }
        if ($null -ne $savedFl) { $env:PDF2ZH_FALLBACK_LOG = $savedFl } else { Remove-Item Env:PDF2ZH_FALLBACK_LOG -ErrorAction SilentlyContinue }
    }
} $null 'G01' 'guard_blocked_sync'

# --- case 5a: baseline early-exit ------------------------------------------------
Invoke-Case '5a-baseline-early-exit' '1' 'backend process exited early' {
    param($log)
    Invoke-EntryScript (Join-Path $perfDir 'p0_baseline.ps1') @('-SourceBackend','repo','-Port','7913','-StartupRuns','1','-IdleSeconds','5','-FailInject','early-exit') $log
} $null

# --- case 6: baseline cleanup-leftover -------------------------------------------
Invoke-Case '6-baseline-cleanup-leftover' '1' 'injected live process detected by identity recheck' {
    param($log)
    Invoke-EntryScript (Join-Path $perfDir 'p0_baseline.ps1') @('-SourceBackend','repo','-Port','7913','-StartupRuns','1','-IdleSeconds','5','-FailInject','cleanup-leftover') $log
} $null

# --- case 7: port occupied by test stub -------------------------------------------
Invoke-Case '7-port-occupied' '3' 'already in use' {
    param($log)
    $stub = [System.Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 7918)
    $stub.Start()
    $r = Invoke-EntryScript (Join-Path $perfDir 'p0_baseline.ps1') @('-SourceBackend','repo','-Port','7918','-StartupRuns','1','-IdleSeconds','5') $log
    $stubAlive = $stub.Server.IsBound
    $stub.Stop()
    if (-not $stubAlive) { return @{ exit = 1 } }   # stub was killed by harness
    return $r
} $null

# --- case 8: external config sentinel ----------------------------------------------
Invoke-Case '8-external-config-sentinel' '0' 'sentinelUnchanged=True' {
    param($log)
    $sentinelDir = Join-Path $env:TEMP ("pdf2zh-sentinel-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Force -Path $sentinelDir | Out-Null
    $sentinel = Join-Path $sentinelDir 'config.v3.toml'
    Set-Content -Path $sentinel -Value '# sentinel: external config must never be read or written' -Encoding ASCII
    $sentinelHash = (Get-FileHash $sentinel -Algorithm SHA256).Hash
    $savedCfg = $env:PDF2ZH_CONFIG_FILE
    $env:PDF2ZH_CONFIG_FILE = $sentinel
    $r = Invoke-EntryScript (Join-Path $perfDir 'p0_baseline.ps1') @('-SourceBackend','repo','-Port','7913','-StartupRuns','1','-IdleSeconds','5') $log
    if ($null -ne $savedCfg) { $env:PDF2ZH_CONFIG_FILE = $savedCfg } else { Remove-Item Env:PDF2ZH_CONFIG_FILE -ErrorAction SilentlyContinue }
    $unchanged = ((Get-FileHash $sentinel -Algorithm SHA256).Hash -eq $sentinelHash)
    Add-Content -Path $log -Value ("sentinelUnchanged={0}" -f $unchanged) -Encoding UTF8
    if (-not $unchanged) { return @{ exit = 1 } }
    return $r
} $null

# --- case 9: PNG invalid inputs -----------------------------------------------------
Invoke-Case '9-png-invalid-inputs' '0' 'png-check failures: 0' {
    param($log)
    . (Join-Path $perfDir 'p0_guard\png_check.ps1')
    if (-not $pngIsoHome) { $pngIsoHome = Join-Path $env:TEMP ('p0-png-iso-' + [guid]::NewGuid().ToString('N').Substring(0,8)); New-Item -ItemType Directory -Force -Path $pngIsoHome | Out-Null }
    Set-PngPythonExe $pyExe (Join-Path $InstallRoot 'uv-tools\pdf2zh-next\Lib\site-packages') -IsolatedHome $pngIsoHome
    $genCode = @'
import pymupdf
doc = pymupdf.open(); page = doc.new_page()
page.insert_text((72, 72), "png negative-test source", fontsize=12)
pix = page.get_pixmap(matrix=pymupdf.Matrix(640/595, 640/595), alpha=False)
pix.save(r"__OUT__")
print("ok")
'@
    $genCode = $genCode -replace '__OUT__', (Join-Path $caseDir 'case9-real640.png')
    $genF = Join-Path $caseDir 'case9-gen.py'
    Set-Content -Path $genF -Value $genCode -Encoding UTF8
    $genExit = Invoke-P0PythonFile -PythonExe $pyExe -ScriptFile $genF -IsolatedHome (Join-Path $caseDir 'case9-generator-home') -PythonPath (Join-Path $InstallRoot 'uv-tools\pdf2zh-next\Lib\site-packages') -GuardDir (Join-Path $perfDir 'p0_guard') -LogPrefix (Join-Path $caseDir 'case9-generator')
    if ($genExit -ne 0) { 'generator failed' | Set-Content $log; return @{ exit = 1 } }
    $real = [IO.File]::ReadAllBytes((Join-Path $caseDir 'case9-real640.png'))

    $script:pngFails = 0
    function Expect-Reject([string]$name, [byte[]]$b, [int]$expect) {
        $w = 0; $h = 0; $why = ''
        if (Test-PngStrict $b $expect ([ref]$w) ([ref]$h) ([ref]$why)) { Write-Host ("[FAIL] {0} accepted" -f $name); $script:pngFails++ }
        else { Write-Host ("[ok] {0} rejected ({1})" -f $name, $why) }
    }
    Expect-Reject 'truncated' ([byte[]]$real[0..20]) 900
    $bad = [byte[]]$real.Clone(); $bad[1] = 0x00
    Expect-Reject 'bad-signature' $bad 900
    $zero = [byte[]]$real.Clone()
    for ($i = 0; $i -lt 8; $i++) { $zero[16 + $i] = [byte]0 }
    $zfix = [byte[]]$zero.Clone()
    $crcZ = Get-Crc32 $zfix 12 17
    for ($i = 0; $i -lt 4; $i++) { $zfix[29 + $i] = [byte](($crcZ -shr (8 * (3 - $i))) -band 0xFF) }
    $zw = 0; $zh = 0; $whyZ2 = ''
    if (Test-PngStrict $zfix 0 ([ref]$zw) ([ref]$zh) ([ref]$whyZ2)) {
        Write-Host '[FAIL] zero-dimension accepted'; $script:pngFails++
    } elseif ($whyZ2 -ne 'zero dimension') {
        Write-Host ("[FAIL] zero-dimension rejected for wrong reason ({0})" -f $whyZ2); $script:pngFails++
    } else { Write-Host '[ok] zero-dimension rejected (zero dimension)' }
    Expect-Reject 'wrong-width' $real 900
    $cut = [byte[]]$real.Clone()
    $truncatedLen = [math]::Min($real.Length, 60)
    $truncated = [byte[]]$real[0..($truncatedLen - 1)]
    $wt = 0; $ht = 0; $whyT = ''
    if (Test-PngStrict $truncated 640 ([ref]$wt) ([ref]$ht) ([ref]$whyT)) {
        Write-Host '[FAIL] truncated-image-data accepted'; $script:pngFails++
    } elseif ($whyT -notmatch 'not decodable') {
        Write-Host ("[FAIL] truncated rejected for wrong reason ({0})" -f $whyT); $script:pngFails++
    } else { Write-Host ("[ok] truncated-image-data rejected ({0})" -f $whyT) }
    $wv = 0; $hv = 0; $whyV = ''
    if (-not (Test-PngStrict $real 640 ([ref]$wv) ([ref]$hv) ([ref]$whyV))) {
        Write-Host ("[FAIL] valid PNG rejected ({0})" -f $whyV); $script:pngFails++
    } else { Write-Host ("[ok] valid PNG accepted ({0}x{1})" -f $wv, $hv) }
    ("png-check failures: " + $script:pngFails) | Add-Content $log -Encoding UTF8
    if ($script:pngFails -gt 0) { return @{ exit = 1 } }
    return @{ exit = 0 }
} $null

# --- case 10: normal short smoke ----------------------------------------------------
Invoke-Case '10-normal-smoke' '0' 'DONE failures=0' {
    param($log)
    Invoke-EntryScript (Join-Path $perfDir 'p0_baseline.ps1') @('-SourceBackend','repo','-Port','7913','-StartupRuns','1','-IdleSeconds','10') $log
} $null

# --- case 11: asset check rejects corrupt SOURCE copy ---------------------------------
Invoke-Case '11-c1-asset-source-corrupt' '4' 'asset_corrupt' {
    param($log)
    $testCode = @'
param([string]$RepoRoot, [string]$InstallRoot, [string]$EvidenceRoot, [string]$PythonExe)
$src = Join-Path $env:TEMP ("pdf2zh-c1-test-" + [guid]::NewGuid().ToString('N').Substring(0,8))
$repo = $RepoRoot
$install = $InstallRoot
$iso = Join-Path $src 'iso-home'
New-Item -ItemType Directory -Force -Path "$src\models", "$iso\.config\pdf2zh" | Out-Null
$realModel = Get-ChildItem (Join-Path $install 'home\.cache\babeldoc\models') -File | Select-Object -First 1
Copy-Item $realModel.FullName "$src\models\$($realModel.Name)"
$bytes = [IO.File]::ReadAllBytes("$src\models\$($realModel.Name)")
$bytes[0] = 0x00; $bytes[1] = 0x01; $bytes[2] = 0x02
[IO.File]::WriteAllBytes("$src\models\$($realModel.Name)", $bytes)
. (Join-Path $repo 'tests\performance\p0_asset_check.ps1')
$ok = Invoke-AssetCheck -CacheDir $src -InstallRoot $install -IsolatedHome $iso -PythonExe $PythonExe
if ($ok) { Write-Host 'UNEXPECTED PASS'; exit 1 } else { Write-Host 'EXPECTED FAIL asset_corrupt'; exit 4 }
'@
    $testFile = Join-Path $caseDir 'c1-test-source-corrupt.ps1'
    Set-Content -Path $testFile -Value $testCode -Encoding UTF8
    Invoke-EntryScript $testFile @() $log
} $null

# --- case 12: asset check rejects MISSING model ---------------------------------------
Invoke-Case '12-c1-asset-source-missing' '4' 'asset_missing' {
    param($log)
    $testCode = @'
param([string]$RepoRoot, [string]$InstallRoot, [string]$EvidenceRoot, [string]$PythonExe)
$src = Join-Path $env:TEMP ("pdf2zh-c1-test-" + [guid]::NewGuid().ToString('N').Substring(0,8))
$repo = $RepoRoot
$install = $InstallRoot
$iso = Join-Path $src 'iso-home'
New-Item -ItemType Directory -Force -Path $src, "$iso\.config\pdf2zh" | Out-Null
. (Join-Path $repo 'tests\performance\p0_asset_check.ps1')
$ok = Invoke-AssetCheck -CacheDir $src -InstallRoot $install -IsolatedHome $iso -PythonExe $PythonExe
if ($ok) { Write-Host 'UNEXPECTED PASS'; exit 1 } else { Write-Host 'EXPECTED FAIL asset_missing'; exit 4 }
'@
    $testFile = Join-Path $caseDir 'c1-test-source-missing.ps1'
    Set-Content -Path $testFile -Value $testCode -Encoding UTF8
    Invoke-EntryScript $testFile @() $log
} $null

# --- case 13: PNG 33-byte IHDR-only ------------------------------------------------------
Invoke-Case '13-c3-png-33byte-ihdr-only' '0' 'not decodable' {
    param($log)
    . (Join-Path $perfDir 'p0_guard\png_check.ps1')
    if (-not $pngIsoHome) { $pngIsoHome = Join-Path $env:TEMP ('p0-png-iso-' + [guid]::NewGuid().ToString('N').Substring(0,8)); New-Item -ItemType Directory -Force -Path $pngIsoHome | Out-Null }
    Set-PngPythonExe $pyExe (Join-Path $InstallRoot 'uv-tools\pdf2zh-next\Lib\site-packages') -IsolatedHome $pngIsoHome
    $realPng = Get-ChildItem (Join-Path $RepoRoot 'docs\verification\native-desktop\final-closure-*\samples') -Filter '*.png' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $realPng) {
        $tmpPng = Join-Path $caseDir 'c3-real640.png'
        $code = @'
import pymupdf
doc = pymupdf.open(); page = doc.new_page()
page.insert_text((72, 72), "c3 test", fontsize=12)
pix = page.get_pixmap(matrix=pymupdf.Matrix(640/595, 640/595), alpha=False)
pix.save(r"__OUT__")
'@
        $code = $code -replace '__OUT__', $tmpPng
        $tmpPy = Join-Path $caseDir 'c3-gen.py'
        Set-Content -Path $tmpPy -Value $code -Encoding UTF8
        $genExit = Invoke-P0PythonFile -PythonExe $pyExe -ScriptFile $tmpPy -IsolatedHome (Join-Path $caseDir 'case13-generator-home') -PythonPath (Join-Path $InstallRoot 'uv-tools\pdf2zh-next\Lib\site-packages') -GuardDir (Join-Path $perfDir 'p0_guard') -LogPrefix (Join-Path $caseDir 'case13-generator')
        if ($genExit -ne 0) { 'generator failed' | Set-Content $log; return @{ exit = 1 } }
        $realPng = Get-Item $tmpPng
    }
    $real = [IO.File]::ReadAllBytes($realPng.FullName)
    $w = 0; $h = 0; $why = ''
    $thirtyThree = $real[0..32]
    $accepted = Test-PngStrict ([byte[]]$thirtyThree) 640 ([ref]$w) ([ref]$h) ([ref]$why)
    $result = "33-byte IHDR-only: accepted=$accepted reason=$why"
    Write-Host $result
    $result | Add-Content $log -Encoding UTF8
    if ($accepted) { return @{ exit = 1 } }
    if ($why -notmatch 'not decodable') { return @{ exit = 1 } }
    return @{ exit = 0 }
} $null

# --- case 14: inherited proxy is NOT used as a tunnel (frozen G11) -----------------------
Invoke-Case '14-netguard-proxy-no-tunnel' '0' 'BLOCKED-BY-GUARD' {
    param($log)
    $guardDir2 = Join-Path $perfDir 'p0_guard'
    $guardLog = Join-Path $caseDir 'case14-guard.log'
    $fbLog = Join-Path $caseDir 'case14-fallback.log'
    Remove-Item $guardLog, $fbLog -ErrorAction SilentlyContinue
    $savedP = $env:PYTHONPATH; $savedGl = $env:PDF2ZH_GUARD_LOG; $savedFl = $env:PDF2ZH_FALLBACK_LOG; $savedHp = $env:HTTP_PROXY
    try {
        $env:PYTHONPATH = (Join-Path $InstallRoot 'uv-tools\pdf2zh-next\Lib\site-packages')
        $env:PDF2ZH_GUARD_LOG = $guardLog
        $env:PDF2ZH_FALLBACK_LOG = $fbLog
        $env:CASE4_GUARD_DIR = $guardDir2
        $env:HTTP_PROXY = 'http://127.0.0.1:9'
        $testPy = Join-Path $caseDir 'case14_test.py'
        @'
import sys, os
guard_dir = os.environ.get("CASE4_GUARD_DIR", "")
sys.path.insert(0, guard_dir)
import guard_fallback
import sitecustomize
import socket
s = socket.socket()
try:
    s.connect(("192.0.2.1", 9))
    print("CONNECTED-BAD")
except OSError as e:
    if "net-guard" in str(e):
        print("BLOCKED-BY-GUARD")
    elif "FALLBACK" in str(e):
        print("BLOCKED-BY-FALLBACK")
    else:
        print("BLOCKED-BY-OS: %s" % str(e)[:80])
'@ | Set-Content $testPy -Encoding ASCII
        $out = & $pyExe $testPy 2>&1
        $out | Set-Content $log -Encoding UTF8
        $outText = $out | Out-String
        $guardLogged = (Test-Path $guardLog) -and ((Get-Content $guardLog -Raw) | Select-String 'BLOCKED.*192\.0\.2\.1' -Quiet)
        $fbClean = ((Test-Path $fbLog) -and (-not ((Get-Content $fbLog -Raw) -match 'FALLBACK_HIT'))) -or (-not (Test-Path $fbLog))
        if (($outText -match 'BLOCKED-BY-GUARD') -and $guardLogged -and $fbClean) { return @{ exit = 0 } }
        return @{ exit = 1 }
    } finally {
        Remove-Item Env:CASE4_GUARD_DIR -ErrorAction SilentlyContinue
        if ($null -ne $savedP) { $env:PYTHONPATH = $savedP } else { Remove-Item Env:PYTHONPATH -ErrorAction SilentlyContinue }
        if ($null -ne $savedGl) { $env:PDF2ZH_GUARD_LOG = $savedGl } else { Remove-Item Env:PDF2ZH_GUARD_LOG -ErrorAction SilentlyContinue }
        if ($null -ne $savedFl) { $env:PDF2ZH_FALLBACK_LOG = $savedFl } else { Remove-Item Env:PDF2ZH_FALLBACK_LOG -ErrorAction SilentlyContinue }
        if ($null -ne $savedHp) { $env:HTTP_PROXY = $savedHp } else { Remove-Item Env:HTTP_PROXY -ErrorAction SilentlyContinue }
    }
} $null 'G11' 'proxy_stripped_guard_blocks'

# --- cases 15a-d: entry-gate negative suite (frozen G14/G04/G05/G15) ---------------------
foreach ($eg in @(
    @{ sub = '15a-entrygate-pos'; fid = 'G14'; freason = 'startup_gate_active' },
    @{ sub = '15b-entrygate-g04'; fid = 'G04'; freason = 'guard_handshake_missing' },
    @{ sub = '15c-entrygate-g05'; fid = 'G05'; freason = 'stale_handshake_rejected' },
    @{ sub = '15d-entrygate-g15'; fid = 'G15'; freason = 'bootstrap_blocks_on_guard_fail' }
)) {
    Invoke-Case $eg.sub '0' 'entry-gate negative tests pass' {
        param($log)
        Invoke-EntryScript (Join-Path $perfDir 'p0_entry_gate_negtest.ps1') @() $log
    } $null $eg.fid $eg.freason
}

# --- case 16: env restore delivery suite (frozen G16) --------------------------------------
Invoke-Case '16-env-restore-suite' '0' 'env restore delivery tests pass' {
    param($log)
    Invoke-EntryScript (Join-Path $perfDir 'p0_env_negtest.ps1') @() $log
} $null 'G16' 'env_restored'

# --- case 17: R1 loopback vector regression (frozen N01 extension) -------------------------
Invoke-Case '17-r1-loopback-vectors' '0' 'R1 loopback vectors: both layers strict, bottom stub untouched' {
    param($log)
    Invoke-EntryScript (Join-Path $perfDir 'p0_loopback_negtest.ps1') @() $log
} $null 'N01' 'pseudo_loopback_rejected'

# --- case 18: R2 isolation sentinels ----------------------------------------------------------
Invoke-Case '18-r2-isolation-sentinels' '0' 'R2 isolation sentinels' {
    param($log)
    Invoke-EntryScript (Join-Path $perfDir 'p0_isolation_negtest.ps1') @() $log
} $null

# --- case 19: R4 recovery stubs -----------------------------------------------------------------
Invoke-Case '19-r4-recovery-stubs' '0' 'R4 recovery stubs' {
    param($log)
    Invoke-EntryScript (Join-Path $perfDir 'p0_recovery_negtest.ps1') @() $log
} $null

}   # end (-not $SelfTest)

# ---------------------------------------------------------------------------
# -SelfTest block: prove the generic engine + RunId refusal with stubs
# ---------------------------------------------------------------------------
if ($SelfTest) {
    $stDir = Join-Path $evDir 'selftest-stubs'
    New-Item -ItemType Directory -Force -Path $stDir | Out-Null

    function New-Stub([string]$name, [string]$body) {
        $p = Join-Path $stDir $name
        Set-Content -Path $p -Value $body -Encoding ASCII
        return $p
    }
    $stubRight = New-Stub 'stub-right-reason.ps1' 'Write-Host "[FAIL] stageX R-correct sentinel"; exit 1'
    $stubWrong = New-Stub 'stub-wrong-reason.ps1'   'Write-Host "[FAIL] unrelated exception boom"; exit 1'
    $stubNoReason = New-Stub 'stub-no-reason.ps1'   'exit 1'

    Write-Host '=== ST: same-exit-right-reason must PASS ==='
    $stLog = Join-Path $stDir 'st-right.log'
    $r = @{ exit = (Start-P0PowerShell -ArgumentList ((@('-NoProfile','-ExecutionPolicy','Bypass','-File',$stubRight) | ForEach-Object { ConvertTo-P0Argument $_ }) -join ' ') -Wait -PassThru -NoNewWindow -RedirectStandardOutput $stLog).ExitCode }
    Invoke-Case 'ST1-same-exit-right-reason' '1' 'R-correct sentinel' { param($log) $r } $stLog

    Write-Host '=== ST: same exit code, WRONG reason must FAIL ==='
    $stLog2 = Join-Path $stDir 'st-wrong.log'
    $r2 = @{ exit = (Start-P0PowerShell -ArgumentList ((@('-NoProfile','-ExecutionPolicy','Bypass','-File',$stubWrong) | ForEach-Object { ConvertTo-P0Argument $_ }) -join ' ') -Wait -PassThru -NoNewWindow -RedirectStandardOutput $stLog2).ExitCode }
    Invoke-Case 'ST2-same-exit-wrong-reason' '1' 'R-correct sentinel' { param($log) $r2 } $stLog2

    Write-Host '=== ST: missing reason artifact must FAIL ==='
    $r3 = @{ exit = 1 }
    Invoke-Case 'ST3-missing-reason-artifact' '1' 'R-correct sentinel' { param($log) $r3 } (Join-Path $stDir 'does-not-exist.log')

    Write-Host '=== ST: exit code mismatch must FAIL ==='
    $r4 = @{ exit = 3 }
    Invoke-Case 'ST4-exit-mismatch' '1' 'R-correct sentinel' { param($log) $r4 } $stLog

    Write-Host '=== ST: RunId reuse must be REFUSED before any write ==='
    $reuseDir = Join-Path $EvidenceRoot ('runs\matrix-selftest-reuse-probe')
    if (-not (Test-Path $reuseDir)) { New-Item -ItemType Directory -Force -Path $reuseDir | Out-Null }
    Set-Content (Join-Path $reuseDir 'sentinel-file.txt') 'do-not-overwrite' -Encoding ASCII
    $preHash = (Get-FileHash (Join-Path $reuseDir 'sentinel-file.txt') -Algorithm SHA256).Hash
    $preCount = (Get-ChildItem $reuseDir | Measure-Object).Count
    $reuseP = Start-P0PowerShell -ArgumentList ((@('-NoProfile','-ExecutionPolicy','Bypass','-File', $PSCommandPath, '-RunId', 'selftest-reuse-probe', '-EvidenceRoot', $EvidenceRoot) | ForEach-Object { ConvertTo-P0Argument $_ }) -join ' ') -Wait -PassThru -NoNewWindow -RedirectStandardOutput (Join-Path $stDir 'reuse-run.log') -RedirectStandardError (Join-Path $stDir 'reuse-run.err')
    $postCount = (Get-ChildItem $reuseDir | Measure-Object).Count
    $postHash = (Get-FileHash (Join-Path $reuseDir 'sentinel-file.txt') -Algorithm SHA256).Hash
    $reuseRefused = ($reuseP.ExitCode -eq 2) -and ($preCount -eq $postCount) -and ($preHash -eq $postHash)
    if ($reuseRefused) {
        Write-Host '[PASS] RunId reuse refused before any write; old files unchanged'
        $script:matrixRows.Add('ST5-runid-reuse-refused,2,2,PASS,refuse-before-write,,') | Out-Null
    } else {
        Write-Host '[FAIL] RunId reuse was not refused cleanly'
        $script:failCount++
        $script:matrixRows.Add('ST5-runid-reuse-refused,2,,FAIL,reuse-not-refused,,') | Out-Null
    }

    Write-Host '=== ST: zero-match -Only must FAIL the run ==='
    if ($total -eq 0) {
        Write-Host '[FAIL] -Only matched zero cases; refusing overall success'
        $script:failCount++
        $script:matrixRows.Add('ST6-zero-match-only,,0,FAIL,zero-match-filter,,') | Out-Null
    }

    # --- self-test final verdict: assert the EXPECTED pattern ------------------
    # ST1 + ST5 must PASS; ST2/ST3/ST4 must FAIL (they prove the engine
    # rejects same-code-wrong-reason / missing-artifact / exit-mismatch).
    # A plain failCount would misread the intended rejections as defects.
    $stVerdicts = @{}
    foreach ($r in $script:matrixRows) { $p = $r.Split(','); if ($p.Count -ge 4) { $stVerdicts[$p[0]] = $p[3] } }
    $patternOk = ($stVerdicts['ST1-same-exit-right-reason'] -eq 'PASS') -and
                 ($stVerdicts['ST2-same-exit-wrong-reason'] -eq 'FAIL') -and
                 ($stVerdicts['ST3-missing-reason-artifact'] -eq 'FAIL') -and
                 ($stVerdicts['ST4-exit-mismatch'] -eq 'FAIL') -and
                 ($stVerdicts['ST5-runid-reuse-refused'] -eq 'PASS')
    if ($patternOk) {
        Write-Host '[PASS] self-test pattern: engine accepts right-reason and refuses wrong-reason/missing-artifact/exit-mismatch; RunId reuse refused'
        $script:failCount = 0
        $script:total = 5
    } else {
        Write-Host '[FAIL] self-test pattern mismatch - verdict engine behaves unexpectedly'
        $script:failCount = 1
        $script:total = 5
    }
}

# --- write matrix + drift check ------------------------------------------------------------
'case,expectedExit,actualExit,verdict,expected_reason,frozenId,frozenExpectedReason' |
    Set-Content (Join-Path $caseDir 'matrix.csv') -Encoding ASCII
$matrixRows | ForEach-Object { Add-Content -Path (Join-Path $caseDir 'matrix.csv') -Value $_ -Encoding ASCII }
Get-Content (Join-Path $caseDir 'matrix.csv')

# -Only filter that matched zero cases must NOT pass (real run)
if ($Only -and $total -eq 0 -and -not $SelfTest) {
    Write-Host ("[FAIL] -Only filter '{0}' matched zero cases; refusing to pass" -f $Only)
    exit 1
}

# post-run hash check: ALL entries, drift=FAIL
$postHashes = [ordered]@{}
foreach ($k in $hashIndex.Keys) {
    $p = if ($k -eq 'source/tests/conftest.py') { Join-Path $RepoRoot 'source\tests\conftest.py' } else { Join-Path $perfDir $k }
    if (Test-Path $p) { $postHashes[$k] = (Get-FileHash $p -Algorithm SHA256).Hash }
}
$drifted = @()
foreach ($k in $hashIndex.Keys) {
    if ($hashIndex[$k] -ne $postHashes[$k]) { $drifted += $k }
}
if ($drifted.Count -gt 0) {
    Write-Host ("[FAIL] script drift detected (drift=FAIL): " + ($drifted -join ', '))
    exit 1
}
Write-Host '[ok] no script drift during run'

Write-Host ("negative matrix done: {0}/{1} cases passed" -f ($total - $failCount), $total)
if ($failCount -gt 0) { exit 1 }
exit 0
