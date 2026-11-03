# Guard wrapper mutation tests (S2/N02): corrupted guard_test.py copies must be
# REJECTED by p0_c1_guard_test.ps1, and the clean copy must pass.
# ASCII only, PS 5.1 safe. Stubs only - no product code, no network beyond the
# guard's own controlled rejects.
#
# Mutations:
#   M-a partial-sync-also-bad : sync hook also disabled -> wrapper must reject
#   M-b no-guard-wrong-exit   : no_guard returns exit 0 -> wrapper must reject
#   M-c deleted-subitem       : no_guard_async result removed -> wrapper rejects
#   M-d fake-os-timeout       : normal sync_blocked replaced by OS-timeout
#                               verdict -> wrapper rejects (no false pass)
#
# Exit: 0 all mutations rejected AND clean copy passes; 1 otherwise.

param(
    [string]$PythonExe = '',
    [string]$EvidenceRoot = '',
    [string]$RepoRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent),
    [string]$InstallRoot = (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) '.local\runtime'),
    [string]$OutDir = ''
)

. (Join-Path $PSScriptRoot 'p0_paths.ps1')
$EvidenceRoot = Resolve-P0EvidenceRoot $RepoRoot $EvidenceRoot

$ErrorActionPreference = 'Continue'
$guardTestPy = Join-Path $RepoRoot 'tests\performance\p0_guard\guard_test.py'
if (-not (Test-Path $guardTestPy)) { Write-Host '[FAIL] guard_test.py missing'; exit 4 }

if (-not $OutDir) {
    $OutDir = Join-Path $EvidenceRoot ("runs\mutations-" +
        (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + $PID)
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$hashes = [ordered]@{}
foreach ($f in @('p0_guard\guard_test.py','p0_guard\sitecustomize.py','p0_c1_guard_test.ps1')) {
    $p = Join-Path $RepoRoot ('tests\performance\' + $f)
    if (Test-Path $p) { $hashes[$f] = (Get-FileHash $p -Algorithm SHA256).Hash }
}
$hashes | ConvertTo-Json | Set-Content (Join-Path $OutDir 'script-hashes.json') -Encoding UTF8

$original = Get-Content $guardTestPy -Raw
$rows = New-Object System.Collections.Generic.List[string]
$script:fails = 0

function Invoke-Wrapper([string]$name, [string]$testPy, [string]$expectedExit) {
    $modeOut = Join-Path $OutDir $name
    New-Item -ItemType Directory -Force -Path $modeOut | Out-Null
    $out = & (Join-Path $RepoRoot 'tests\performance\p0_c1_guard_test.ps1') -RepoRoot $RepoRoot -InstallRoot $InstallRoot -PythonExe $PythonExe -EvidenceRoot $EvidenceRoot -OutDir $modeOut -GuardTestPy $testPy 2>&1
    $exit = $LASTEXITCODE
    $verdict = if ("$exit" -eq "$expectedExit") { 'PASS' } else { 'FAIL' }
    if ($verdict -eq 'FAIL') { $script:fails++ }
    $rows.Add(("{0},{1},{2},{3}" -f $name, $expectedExit, $exit, $verdict)) | Out-Null
    Write-Host ("  {0}: exit={1} expected={2} verdict={3}" -f $name, $exit, $expectedExit, $verdict)
}

function New-Mutated([string]$name, [hashtable]$replacements, [string]$prepend = '') {
    $content = $original
    foreach ($k in $replacements.Keys) {
        if (-not $content.Contains($k)) {
            Write-Host ("[FATAL] mutation {0}: pattern not found: {1}" -f $name, $k)
            return $null
        }
        $content = $content.Replace($k, $replacements[$k])
    }
    if ($prepend) { $content = $prepend + "`n" + $content }
    $p = Join-Path $OutDir ("guard_test_" + $name + ".py")
    Set-Content -Path $p -Value $content -Encoding UTF8
    # M1 fix: the mutated copy resolves _guard_dir to its OWN directory; the
    # explicit-import chain (guard_fallback -> sitecustomize) requires the two
    # modules to sit next to the copy.
    Copy-Item (Join-Path $perfDir 'p0_guard\guard_fallback.py') (Join-Path $OutDir 'guard_fallback.py') -Force
    Copy-Item (Join-Path $perfDir 'p0_guard\sitecustomize.py') (Join-Path $OutDir 'sitecustomize.py') -Force
    return $p
}

# --- clean control -------------------------------------------------------------
$perfDir = Join-Path $RepoRoot 'tests\performance'
Invoke-Wrapper 'clean' $guardTestPy '0'

# --- M-a: sync hook also disabled (partial must show sync NOT guarded) ---------
$ma = New-Mutated 'partial-sync-also-bad' @{
    'import sitecustomize' = 'os.environ["PDF2ZH_GUARD_SKIP"] = "sync,async"' + "`n" + 'import sitecustomize'
}
if ($ma) { }
Invoke-Wrapper 'M-a' $ma '1'

# --- M-b: no_guard returns wrong exit code --------------------------------------
$mb = New-Mutated 'no-guard-wrong-exit' @{ 'sys.exit(0 if all_pass else 1)' = 'sys.exit(0)' }
Invoke-Wrapper 'M-b' $mb '1'

# --- M-c: delete a required result subitem (no_guard_async) ---------------------
$mc = New-Mutated 'deleted-subitem' @{
    '# === Summary ===' = 'if "no_guard_async" in RESULTS:' + "`n" + '    del RESULTS["no_guard_async"]' + "`n" + '# === Summary ==='
}
Invoke-Wrapper 'M-c' $mc '1'

# --- M-d: fake normal timeout (OS rejection counted as if blocked) --------------
$fakeInjection = @'
if TEST_MODE == "normal" and "sync_blocked" in RESULTS:
    RESULTS["sync_blocked"] = {"rejected": True, "error": "connection timed out", "new_guard_blocks": 0, "new_fallback_hits": 0, "source": "os", "passed": False, "reason": "simulated OS timeout mutation"}
'@
$md = New-Mutated 'fake-timeout' @{ '# === Summary ===' = $fakeInjection + "`n" + '# === Summary ===' }
Invoke-Wrapper 'M-d' $md '1'

'case,expectedExit,actualExit,verdict' | Set-Content (Join-Path $OutDir 'matrix.csv') -Encoding ASCII
$rows | ForEach-Object { Add-Content (Join-Path $OutDir 'matrix.csv') $_ -Encoding ASCII }
Get-Content (Join-Path $OutDir 'matrix.csv')
if ($script:fails -gt 0) { Write-Host '[FAIL] mutation tests incomplete: some corrupted copies were NOT rejected'; exit 1 }
Write-Host '[PASS] all mutations rejected; clean copy passed'
exit 0

