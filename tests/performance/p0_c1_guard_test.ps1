# C1 comprehensive guard test wrapper v3 (ASCII only, PS 5.1 safe)
# S2/S3 fixes: verdicts driven by the PARSED testResults JSON (not free text);
# PYTHONPATH is a managed env key (saved with existed/value, restored in
# finally - never destroyed); per-mode exit codes validated explicitly;
# required subitems enforced (missing subitem = mode failure).
#
# Modes:
#   normal   - guard fully active, exit 0 required, all subtests passed,
#              fallback zero hits, guard log has BLOCKED entries + GUARD_ACTIVE
#   no_guard - guard absent, exit 1 required, sync/async/dns EACH caught with
#              source=fallback, fallback log has FALLBACK_ACTIVE + hits >= 3
#   partial  - guard partial (skip async), exit 1 required, sync source=guard
#              AND passed, async source=fallback AND passed
#
# Exit: 0 all modes pass; 1 any failure; 4 prerequisite missing.

param(
    [string]$RepoRoot = 'D:\paper\PDFMathTranslate-next',
    [string]$InstallRoot = 'D:\paper\pdf2zh-install-test',
    [string]$OutDir = '',
    [string]$GuardTestPy = ''   # mutation tests point this at a corrupted copy
)

$ErrorActionPreference = 'Continue'
. (Join-Path $RepoRoot 'tests\performance\p0_env.ps1')

$guardDir = Join-Path $RepoRoot 'tests\performance\p0_guard'
$python = Get-ChildItem (Join-Path $InstallRoot 'uv-python') -Recurse -Filter python.exe |
    Select-Object -First 1 -ExpandProperty FullName
$sitePackages = Join-Path $InstallRoot 'uv-tools\pdf2zh-next\Lib\site-packages'
if (-not $python -or -not (Test-Path $guardDir)) { Write-Host '[FAIL] prerequisite missing'; exit 4 }
if (-not $GuardTestPy) { $GuardTestPy = Join-Path $guardDir 'guard_test.py' }
if (-not (Test-Path $GuardTestPy)) { Write-Host ("[FAIL] guard test script missing: " + $GuardTestPy); exit 4 }

# S6: default output goes to THIS round's evidence root (never reuse old roots)
if (-not $OutDir) {
    $OutDir = Join-Path $RepoRoot ("docs\verification\native-desktop\r2-integrated-20261003-01\runs\guard-test-" +
        (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + $PID)
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# C2: runtime hash index covers ALL actual dependencies (not the old ten).
# Keys MUST be repo-relative and resolvable by the checker (M4): mutation
# copy hashes go to a separate mutation-run marker file, never into the main index.
$hashFiles = @(
    'p0_guard\guard_test.py','p0_guard\guard_fallback.py','p0_guard\sitecustomize.py',
    'p0_guard\entry_gate.py','p0_guard\entry_wrapper.py','p0_env.ps1','p0_result.ps1',
    'p0_evidence_check.ps1','p0_c1_guard_test.ps1'
)
$hashes = [ordered]@{}
foreach ($f in $hashFiles) {
    $p = Join-Path $RepoRoot ('tests\performance\' + $f)
    if (Test-Path $p) { $hashes[$f] = (Get-FileHash $p -Algorithm SHA256).Hash }
}
if ($GuardTestPy) {
    $defaultPy = Join-Path $guardDir 'guard_test.py'
    if ((Resolve-Path $GuardTestPy).Path -ne (Resolve-Path $defaultPy -ErrorAction SilentlyContinue)) {
        @{ encountered_test_script = $GuardTestPy
           encountered_test_script_sha256 = (Get-FileHash $GuardTestPy -Algorithm SHA256).Hash
           note = 'mutation/variant run: the variant script is not a repo file; hash recorded here, not in script-hashes.json (M4)' } |
            ConvertTo-Json | Set-Content (Join-Path $OutDir 'mutation-run-info.json') -Encoding UTF8
    } else {
        $hashes['p0_guard\guard_test.py'] = (Get-FileHash $GuardTestPy -Algorithm SHA256).Hash
    }
}
$hashes | ConvertTo-Json | Set-Content (Join-Path $OutDir 'script-hashes.json') -Encoding UTF8

# Required result subitems per mode (missing subitem = mode failure)
$requiredSubitems = @{
    normal   = @('guard_loaded','fallback_active','fallback_confirmed','sync_blocked',
                 'connect_ex_blocked','dns_blocked','async_blocked','httpx_blocked',
                 'loopback_allowed','fallback_zero_hits','pseudo_loopback_predicate',
                 'pseudo_loopback_connect_127audit','pseudo_loopback_connect_localhostaudit',
                 'leading_zero_octet_blocked','leading_zero_long_blocked',
                 'empty_host_rejected')
    no_guard = @('guard_loaded','fallback_active','fallback_confirmed',
                 'no_guard_sync','no_guard_async','no_guard_dns')
    partial  = @('guard_loaded','fallback_active','fallback_confirmed',
                 'partial_sync_guarded','partial_async_fallback')
}

$totalFails = 0
$modeResults = [ordered]@{}
$envNames = @('HTTP_PROXY','HTTPS_PROXY','ALL_PROXY','PDF2ZH_GUARD_LOG','PDF2ZH_FALLBACK_LOG',
    'PDF2ZH_GUARD_TEST_MODE','PDF2ZH_GUARD_SKIP','PYTHONPATH')

foreach ($mode in @('normal', 'no_guard', 'partial')) {
    $modeDir = Join-Path $OutDir $mode
    New-Item -ItemType Directory -Force -Path $modeDir | Out-Null
    $guardLog = Join-Path $modeDir 'guard.log'
    $fallbackLog = Join-Path $modeDir 'fallback.log'
    $outputLog = Join-Path $modeDir 'output.log.txt'
    $errLog = Join-Path $modeDir 'stderr.log.txt'
    $resultsJson = Join-Path $modeDir 'testResults.json'
    Remove-Item $guardLog, $fallbackLog, $resultsJson -ErrorAction SilentlyContinue

    Write-Host "`n=== Guard test mode: $mode ==="

    # S3: Set-ChildEnvBlock saves existed+value for EVERY managed name
    # (including PYTHONPATH) and clears them; Restore-ChildEnv in finally
    # restores originals and deletes keys that did not exist before.
    $saved = Set-ChildEnvBlock $envNames
    try {
        $env:PYTHONPATH = $sitePackages  # for httpx only; guardDir deliberately NOT included

        if ($mode -eq 'normal') {
            $env:PDF2ZH_GUARD_LOG = $guardLog
            $env:PDF2ZH_FALLBACK_LOG = $fallbackLog
            $env:PDF2ZH_GUARD_TEST_MODE = 'normal'
        } elseif ($mode -eq 'no_guard') {
            $env:PDF2ZH_FALLBACK_LOG = $fallbackLog
            $env:PDF2ZH_GUARD_TEST_MODE = 'no_guard'
        } elseif ($mode -eq 'partial') {
            $env:PDF2ZH_GUARD_LOG = $guardLog
            $env:PDF2ZH_FALLBACK_LOG = $fallbackLog
            $env:PDF2ZH_GUARD_TEST_MODE = 'partial'
            $env:PDF2ZH_GUARD_SKIP = 'async'
        }
        $env:PDF2ZH_RESULTS_PATH = $resultsJson

        $raw = & $python -u $GuardTestPy 2>&1
        $exitCode = $LASTEXITCODE

        $raw | Set-Content $outputLog -Encoding UTF8
        $raw | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } |
            Set-Content $errLog -Encoding UTF8

        # S2: verdicts are driven by the parsed structured results
        $testResults = $null
        if (Test-Path $resultsJson) {
            try { $testResults = Get-Content $resultsJson -Raw | ConvertFrom-Json } catch { $testResults = $null }
        }

        $subitems = $requiredSubitems[$mode]
        $missingSubitems = @()
        $failedSubitems = @()
        if ($null -eq $testResults) {
            $missingSubitems = @('<no testResults JSON>')
        } else {
            foreach ($si in $subitems) {
                if (-not $testResults.PSObject.Properties[$si]) { $missingSubitems += $si }
                elseif (-not $testResults.$si.passed) { $failedSubitems += $si }
            }
        }

        $modePass = $false
        $reason = ''
        $guardText = if (Test-Path $guardLog) { Get-Content $guardLog -Raw } else { '' }
        $fbText = if (Test-Path $fallbackLog) { Get-Content $fallbackLog -Raw } else { '' }
        $guardActive = $guardText -match 'GUARD_ACTIVE'
        $blockedCount = ([regex]::Matches($guardText, 'BLOCKED')).Count
        $fbHits = ([regex]::Matches($fbText, 'FALLBACK_HIT')).Count

        if ($mode -eq 'normal') {
            $expectedExit = 0
            $modePass = ($exitCode -eq 0 -and $guardActive -and $blockedCount -ge 4 -and
                         $fbHits -eq 0 -and $missingSubitems.Count -eq 0 -and $failedSubitems.Count -eq 0)
            $reason = "exit=$exitCode(expected $expectedExit) guardActive=$guardActive blocked=$blockedCount " +
                      "fbHits=$fbHits missingSubitems=[$($missingSubitems -join ',')] " +
                      "failedSubitems=[$($failedSubitems -join ',')]"
        } elseif ($mode -eq 'no_guard') {
            $expectedExit = 1
            $fbActive = $fbText -match 'FALLBACK_ACTIVE'
            # EVERY specified subitem must be individually caught by fallback
            $allFb = $true
            $srcDetail = @()
            if ($testResults) {
                foreach ($si in @('no_guard_sync','no_guard_async','no_guard_dns')) {
                    if ($testResults.PSObject.Properties[$si]) {
                        $src = $testResults.$si.source
                        $srcDetail += ("{0}={1}" -f $si, $src)
                        if ($src -ne 'fallback' -or -not $testResults.$si.passed) { $allFb = $false }
                    } else { $allFb = $false }
                }
            } else { $allFb = $false }
            $modePass = ($exitCode -eq 1 -and $fbActive -and $fbHits -ge 3 -and $allFb -and
                         -not $guardActive -and $missingSubitems.Count -eq 0 -and $failedSubitems.Count -eq 0)
            $reason = "exit=$exitCode(expected $expectedExit) fbActive=$fbActive fbHits=$fbHits " +
                      "guardActive=$guardActive perItem=[$($srcDetail -join ' ')] " +
                      "missing=[$($missingSubitems -join ',')] failed=[$($failedSubitems -join ',')]"
        } else {
            $expectedExit = 1
            # partial: sync MUST be guarded by guard, async MUST hit fallback
            $syncSrc = if ($testResults -and $testResults.PSObject.Properties['partial_sync_guarded']) { $testResults.partial_sync_guarded.source } else { '<missing>' }
            $asyncSrc = if ($testResults -and $testResults.PSObject.Properties['partial_async_fallback']) { $testResults.partial_async_fallback.source } else { '<missing>' }
            $syncOk = ($syncSrc -eq 'guard')
            $asyncOk = ($asyncSrc -eq 'fallback')
            $modePass = ($exitCode -eq 1 -and $syncOk -and $asyncOk -and
                         $missingSubitems.Count -eq 0 -and $failedSubitems.Count -eq 0)
            $reason = "exit=$exitCode(expected $expectedExit) sync=$syncSrc async=$asyncSrc " +
                      "missing=[$($missingSubitems -join ',')] failed=[$($failedSubitems -join ',')]"
        }

        $modeResults[$mode] = @{
            exitCode = $exitCode
            expectedExit = $expectedExit
            passed = $modePass
            blockedCount = $blockedCount
            fallbackHits = $fbHits
            missingSubitems = $missingSubitems
            failedSubitems = $failedSubitems
            reason = $reason
        }
        Write-Host ("  Mode {0}: exit={1} passed={2} :: {3}" -f $mode, $exitCode, $modePass, $reason)
    } finally {
        # S3: restores original values AND deletes keys created during the run;
        # PYTHONPATH is in $envNames so it is restored, never destroyed.
        Restore-ChildEnv $saved
    }

    if (-not $modeResults[$mode].passed) { $totalFails++ }
}

# === Summary ===
$modeResults | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $OutDir 'summary.json') -Encoding UTF8

Write-Host "`n=== Guard test overall: $($modeResults.Count - $totalFails)/$($modeResults.Count) modes passed ==="
foreach ($m in $modeResults.Keys) {
    Write-Host ("  {0}: {1}" -f $m, $(if ($modeResults[$m].passed) { 'PASS' } else { 'FAIL' }))
}
if ($totalFails -gt 0) { exit 1 }
Write-Host '[PASS] All guard test modes pass'
exit 0


