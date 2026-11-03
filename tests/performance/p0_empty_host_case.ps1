# Frozen-case G12 driver (ASCII only, PS 5.1 safe): runs the empty-host probe
# under the same guard/fallback activation envs used by the guard tests and
# records command + exit + output into the round evidence root.
# Frozen expectation: exit 1 (rejection observed), reason empty_host_rejected.
# Exit: 0 when the probe produced the frozen exit 1; 1 otherwise.

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
. (Join-Path $RepoRoot 'tests\performance\p0_env.ps1')

$guardDir = Join-Path $RepoRoot 'tests\performance\p0_guard'
$python = Resolve-P0Python $InstallRoot $PythonExe
if (-not $python -or -not (Test-Path (Join-Path $guardDir 'empty_host_probe.py'))) {
    Write-Host '[FAIL] prerequisite missing'; exit 4
}
if (-not $OutDir) {
    $OutDir = Join-Path $EvidenceRoot ("runs\empty-host-" +
        (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + $PID)
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

@{
    'p0_guard\empty_host_probe.py' = (Get-FileHash (Join-Path $guardDir 'empty_host_probe.py') -Algorithm SHA256).Hash
    'p0_guard\sitecustomize.py' = (Get-FileHash (Join-Path $guardDir 'sitecustomize.py') -Algorithm SHA256).Hash
    'p0_guard\guard_fallback.py' = (Get-FileHash (Join-Path $guardDir 'guard_fallback.py') -Algorithm SHA256).Hash
    'p0_empty_host_case.ps1' = (Get-FileHash $PSCommandPath -Algorithm SHA256).Hash
} | ConvertTo-Json | Set-Content (Join-Path $OutDir 'script-hashes.json') -Encoding UTF8

$guardLog = Join-Path $OutDir 'guard.log'
$fallbackLog = Join-Path $OutDir 'fallback.log'
$saved = Set-ChildEnvBlock @('PDF2ZH_GUARD_LOG','PDF2ZH_FALLBACK_LOG','PYTHONPATH')
try {
    # activate BOTH layers (predicates only exist when their env is set)
    $env:PDF2ZH_GUARD_LOG = $guardLog
    $env:PDF2ZH_FALLBACK_LOG = $fallbackLog
    $env:PYTHONPATH = (Join-Path $InstallRoot 'uv-tools\pdf2zh-next\Lib\site-packages')
    $out = & $python -u (Join-Path $guardDir 'empty_host_probe.py') 2>&1
    $exit = $LASTEXITCODE
} finally {
    Restore-ChildEnv $saved
}
$out | Set-Content (Join-Path $OutDir 'probe-output.log.txt') -Encoding UTF8
$exit | Set-Content (Join-Path $OutDir 'probe-exit.txt') -Encoding ASCII
Write-Host ("probe exit: {0}" -f $exit)
Write-Host ("output: {0}" -f (($out | Out-String).Trim()))
if ($exit -eq 1) { Write-Host '[PASS] G12 empty-host rejection observed (frozen exit 1)'; exit 0 }
Write-Host '[FAIL] G12 empty-host probe did not produce the frozen exit 1'
exit 1

