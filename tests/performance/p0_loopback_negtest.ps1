# R1 loopback vector driver (ASCII only, PS 5.1 safe).
# Runs p0_guard/loopback_vectors.py with BOTH layers activated and a results
# JSON artifact; also asserts the OS-side parse divergence fact locally
# (AI_NUMERICHOST only, no DNS, no connection) as supporting evidence.
# Exit: 0 vectors pass; 1 any vector fails; 4 prerequisite missing.

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
if (-not $python -or -not (Test-Path (Join-Path $guardDir 'loopback_vectors.py'))) {
    Write-Host '[FAIL] prerequisite missing'; exit 4
}
if (-not $OutDir) {
    $OutDir = Join-Path $RepoRoot ("docs\verification\native-desktop\r2-integrated-20261003-01\runs\loopback-vectors-" +
        (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + $PID)
}
if ((Test-Path $OutDir) -and (Get-ChildItem $OutDir -ErrorAction SilentlyContinue)) {
    Write-Host ("[FAIL] OutDir already exists and is non-empty (refuse overwrite): " + $OutDir); exit 2
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

@{
    'p0_guard\sitecustomize.py' = (Get-FileHash (Join-Path $guardDir 'sitecustomize.py') -Algorithm SHA256).Hash
    'p0_guard\guard_fallback.py' = (Get-FileHash (Join-Path $guardDir 'guard_fallback.py') -Algorithm SHA256).Hash
    'p0_guard\loopback_vectors.py' = (Get-FileHash (Join-Path $guardDir 'loopback_vectors.py') -Algorithm SHA256).Hash
    'p0_loopback_negtest.ps1' = (Get-FileHash $PSCommandPath -Algorithm SHA256).Hash
} | ConvertTo-Json | Set-Content (Join-Path $OutDir 'script-hashes.json') -Encoding UTF8

# --- supporting fact: OS numeric parse divergence (AI_NUMERICHOST only) ----
# pure numeric resolution, NO DNS, NO connection. Records what the OS would do
# with '0127.0.0.1' so the rejection policy is visibly justified.
$osProbe = Join-Path $OutDir 'os-numeric-parse.txt'
$saved = Set-ChildEnvBlock @('PDF2ZH_GUARD_LOG','PDF2ZH_FALLBACK_LOG','PYTHONPATH')
try {
    $env:PDF2ZH_GUARD_LOG = Join-Path $OutDir 'guard.log'
    $env:PDF2ZH_FALLBACK_LOG = Join-Path $OutDir 'fallback.log'
    $env:PDF2ZH_VECTORS_PATH = Join-Path $OutDir 'vectors-result.json'
    $env:PYTHONPATH = (Join-Path $InstallRoot 'uv-tools\pdf2zh-next\Lib\site-packages')
    & $python -c "import socket; ai=socket.AI_NUMERICHOST; [print(repr(h), '->', socket.getaddrinfo(h, None, flags=ai)[0][4][0]) for h in ['127.0.0.1','0127.0.0.1','00127.0.0.1']]" 2>&1 |
        Set-Content $osProbe -Encoding UTF8
    $out = & $python -u (Join-Path $guardDir 'loopback_vectors.py') 2>&1
    $exit = $LASTEXITCODE
} finally {
    Restore-ChildEnv $saved
}
$out | Set-Content (Join-Path $OutDir 'vectors-output.log.txt') -Encoding UTF8
$exit | Set-Content (Join-Path $OutDir 'vectors-exit.txt') -Encoding ASCII
Get-Content $osProbe
Write-Host ("vectors exit: {0}" -f $exit)
if ($exit -ne 0) { Write-Host '[FAIL] R1 vector regression failed'; exit 1 }
Write-Host '[PASS] R1 loopback vectors: both layers strict, bottom stub untouched'
exit 0
