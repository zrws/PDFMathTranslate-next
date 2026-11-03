# Isolated pytest runner v3 with real-home protection evidence (ASCII only)
# F4/F6 remediation: parent PYTHONPATH restored; before/after snapshots of the
# scoped real dirs are SAVED to disk (sanitized relative paths + size + mtime;
# large files size-only; read failures recorded, never silently ignored);
# result.json binds runner/conftest/script hashes.
# Exit: 0 pytest passed AND real dirs unchanged; 1 pytest failed;
#       4 runner prerequisites missing; 5 real-home changed (isolation breach);
#       6 snapshot read failures occurred (evidence incomplete, not "no change")

param(
    [string]$InstallRoot = 'D:\paper\pdf2zh-install-test',
    [string]$RepoRoot = 'D:\paper\PDFMathTranslate-next',
    [string]$OutDir = ''
)

$ErrorActionPreference = 'Stop'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
if (-not $OutDir) {
    $OutDir = Join-Path $RepoRoot ("docs\verification\native-desktop\r2-integrated-20261003-01\runs\pytest-" + $stamp)
}
$runDir = $OutDir
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$venvPy = 'D:\paper\pdf2zh-test-venv\Scripts\python.exe'
if (-not (Test-Path $venvPy)) { Write-Host '[FAIL] test venv missing'; exit 4 }

$realDirs = @(
    (Join-Path $env:USERPROFILE '.config\pdf2zh'),
    (Join-Path $env:USERPROFILE '.cache\pdf2zh_next'),
    (Join-Path $env:USERPROFILE '.cache\babeldoc'),
    (Join-Path $RepoRoot 'source\pdf2zh_files')
)

# M5 (gate A): pytest runs the product test-suite; it must run under the net
# guard like every other entry that imports product code. Loopback is allowed
# (test HTTP APIs bind loopback); any blocked outbound attempt fails the run.
$guardDir = Join-Path $RepoRoot 'tests\performance\p0_guard'
if (-not (Test-Path (Join-Path $guardDir 'sitecustomize.py'))) { Write-Host '[FAIL] guard module missing'; exit 4 }
$guardLog = Join-Path $runDir 'guard.log'
Remove-Item $guardLog -ErrorAction SilentlyContinue

$savedPy = $env:PYTHONPATH
$savedEap = $ErrorActionPreference
$savedGl = $env:PDF2ZH_GUARD_LOG
$savedGd = $env:PDF2ZH_GUARD_DIR
$savedRi = $env:PDF2ZH_RUN_ID

function Snapshot([string]$tag) {
    # sanitized listing persisted to disk: relative path|size|mtimeUtc|sha256
    # (files < 1MB hashed; larger files size-only; read failures recorded)
    $file = Join-Path $runDir ("snapshot-$tag.txt")
    $readErrors = New-Object System.Collections.Generic.List[string]
    $rows = New-Object System.Collections.Generic.List[string]
    foreach ($d in $realDirs) {
        $rows += ("#DIR {0} :: {1}" -f $d, ($(if (Test-Path $d) { 'present' } else { 'absent' })))
        if (-not (Test-Path $d)) { continue }
        $files = @(Get-ChildItem $d -Recurse -File -ErrorAction SilentlyContinue)
        foreach ($f in $files) {
            $rel = $f.FullName.Substring($d.Length).TrimStart('\')
            try {
                $h = if ($f.Length -lt 1MB) { (Get-FileHash $f.FullName -Algorithm SHA256 -ErrorAction Stop).Hash } else { 'LARGE(size-only)' }
                $rows += ("{0}|{1}|{2}|{3}" -f $rel, $f.Length, $f.LastWriteTimeUtc.Ticks, $h)
            } catch {
                $readErrors.Add(("$d\$rel : " + $_.Exception.Message))
                $rows += ("{0}|{1}|{2}|READ-ERROR" -f $rel, $f.Length, $f.LastWriteTimeUtc.Ticks)
            }
        }
    }
    $rows | Set-Content -Path $file -Encoding UTF8
    return @{ rows = $rows; readErrors = $readErrors; file = $file }
}

$before = Snapshot 'before'

# run pytest with repo-source-first PYTHONPATH + net guard; conftest handles home isolation
$env:PYTHONPATH = $guardDir + ';' + (Join-Path $RepoRoot 'source') + ';' + (Join-Path $InstallRoot 'uv-tools\pdf2zh-next\Lib\site-packages')
$env:PDF2ZH_GUARD_LOG = $guardLog
$env:PDF2ZH_GUARD_DIR = $guardDir
$env:PDF2ZH_RUN_ID = ("pytest-" + $stamp)
# R2: strip any inherited PDF2ZH_CONFIG_FILE so conftest's isolated value is
# the only one the test process can see (saved/restored with existed/value)
$savedCfg = $env:PDF2ZH_CONFIG_FILE
Remove-Item Env:PDF2ZH_CONFIG_FILE -ErrorAction SilentlyContinue
$pytestLog = Join-Path $runDir 'pytest-full-output.txt'
$ErrorActionPreference = 'Continue'   # native stderr records must not terminate (PS 5.1)
try {
    Push-Location (Join-Path $RepoRoot 'source')
    & $venvPy -m pytest tests -q --no-header -v 2>&1 | ForEach-Object { "$_" } | Set-Content -Path $pytestLog -Encoding UTF8
    $pytestRc = $LASTEXITCODE
} finally {
    Pop-Location
    $ErrorActionPreference = 'Stop'
    if ($null -ne $savedPy) { $env:PYTHONPATH = $savedPy } else { Remove-Item Env:PYTHONPATH -ErrorAction SilentlyContinue }
    if ($null -ne $savedGl) { $env:PDF2ZH_GUARD_LOG = $savedGl } else { Remove-Item Env:PDF2ZH_GUARD_LOG -ErrorAction SilentlyContinue }
    if ($null -ne $savedGd) { $env:PDF2ZH_GUARD_DIR = $savedGd } else { Remove-Item Env:PDF2ZH_GUARD_DIR -ErrorAction SilentlyContinue }
    if ($null -ne $savedRi) { $env:PDF2ZH_RUN_ID = $savedRi } else { Remove-Item Env:PDF2ZH_RUN_ID -ErrorAction SilentlyContinue }
    if ($null -ne $savedCfg) { $env:PDF2ZH_CONFIG_FILE = $savedCfg } else { Remove-Item Env:PDF2ZH_CONFIG_FILE -ErrorAction SilentlyContinue }
}
Write-Host ("pytest exit code: {0}" -f $pytestRc)

# B2/S1: guard evidence for the pytest run - GUARD_ACTIVE required, and NO
# blocked outbound attempt: blocked => real home/cache/proxy escape attempts
if ((Test-Path $guardLog) -and (Select-String -Path $guardLog -Pattern 'GUARD_ACTIVE' -Quiet)) {
    $blocked = (Select-String -Path $guardLog -Pattern 'BLOCKED' -ErrorAction SilentlyContinue | Measure-Object).Count
    Copy-Item $guardLog (Join-Path $runDir 'guard.log.txt') -Force
    if ($blocked -gt 0) {
        Write-Host ("[FAIL] net-guard blocked {0} outbound attempts during pytest (see guard log)" -f $blocked)
        exit 5
    }
    Write-Host '[PASS] net-guard active for pytest: zero outbound attempts'
} else {
    Write-Host '[FAIL] guard.log without GUARD_ACTIVE: guard did not load in pytest run'
    exit 5
}

$after = Snapshot 'after'

# diff from persisted listings (per-dir block comparison)
function Get-DirRows([string]$snapFile, [string]$dir) {
    $rows = @()
    $in = $false
    foreach ($line in (Get-Content $snapFile)) {
        if ($line -like '#DIR *') { $in = ($line -eq ("#DIR " + $dir + " :: present")); continue }
        if ($in) { $rows += $line }
    }
    return $rows
}
$changesAll = New-Object System.Collections.Generic.List[string]
foreach ($d in $realDirs) {
    $bRows = @(Get-DirRows $before.file $d)
    $aRows = @(Get-DirRows $after.file $d)
    foreach ($c in (Compare-Object $bRows $aRows)) {
        $side = if ($c.SideIndicator -eq '<=') { 'removed-or-changed(before)' } else { 'added-or-changed(after)' }
        $changesAll.Add(("{0} : {1} : {2}" -f $d, $side, $c.InputObject))
    }
}
if ($changesAll.Count -gt 0) { $changesAll | Set-Content (Join-Path $runDir 'real-home-changes.txt') -Encoding UTF8 }
else { '(no changes - real user dirs identical before/after)' | Set-Content (Join-Path $runDir 'real-home-changes.txt') -Encoding UTF8 }
$readErrors = @($before.readErrors + $after.readErrors)
if ($readErrors.Count -gt 0) { $readErrors | Set-Content (Join-Path $runDir 'snapshot-read-errors.txt') -Encoding UTF8 }
else { '(no snapshot read failures)' | Set-Content (Join-Path $runDir 'snapshot-read-errors.txt') -Encoding UTF8 }

function Sha([string]$p) { if (Test-Path $p) { return (Get-FileHash $p -Algorithm SHA256).Hash } return $null }

$result = [ordered]@{
    pytestExitCode = $pytestRc
    realHomeChanged = ($changesAll.Count -gt 0)
    changeCount = $changesAll.Count
    snapshotReadErrorCount = $readErrors.Count
    runDir = $runDir
    scopeNote = 'snapshot scope limited to the four dirs listed in real-home-changes.txt; configs/values not captured, only path|size|mtime|sha256'
    runnerSha256 = Sha $PSCommandPath
    conftestSha256 = Sha (Join-Path $RepoRoot 'source\tests\conftest.py')
    baselineSha256 = Sha (Join-Path $RepoRoot 'tests\performance\p0_baseline.ps1')
    note = 'conftest.py redirects HOME/USERPROFILE/CWD per session; changes here would indicate isolation breach; read failures listed in snapshot-read-errors.txt'
}
$result | ConvertTo-Json | Set-Content (Join-Path $runDir 'result.json') -Encoding UTF8

if ($readErrors.Count -gt 0) { Write-Host ("[WARN] {0} snapshot read failures - recorded, not treated as no-change" -f $readErrors.Count) }
if ($changesAll.Count -gt 0) {
    Write-Host '[FAIL] real home changed during pytest:'
    $changesAll | Select-Object -First 10
    Write-Host ("evidence dir: {0}" -f $runDir)
    exit 5
}
Write-Host '[PASS] real user dirs unchanged'
Write-Host ("evidence dir: {0}" -f $runDir)
if ($pytestRc -ne 0) { exit 1 }
if ($readErrors.Count -gt 0) { exit 6 }
exit 0

