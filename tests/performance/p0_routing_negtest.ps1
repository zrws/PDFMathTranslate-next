# Local fixtures are resolver tests, never backend evidence or frozen coverage.
param(
    [string]$RepoRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent),
    [string]$EvidenceRoot = '', [string]$OutDir = ''
)
. (Join-Path $PSScriptRoot 'p0_paths.ps1')
. (Join-Path $PSScriptRoot 'p0_runs.ps1')
$ErrorActionPreference = 'Stop'
$EvidenceRoot = Resolve-P0EvidenceRoot $RepoRoot $EvidenceRoot
if (-not $OutDir) { $OutDir = Join-Path $EvidenceRoot ('routing-fixtures/test-' + [guid]::NewGuid().ToString('N')) }
if (Test-Path -LiteralPath $OutDir) { throw 'output already exists' }
New-Item -ItemType Directory -Path (Join-Path $OutDir 'runs') -Force | Out-Null
$checks = @()
foreach ($entry in @('p0_probe_perprocess.ps1','p0_probe_attribution.ps1','p0_baseline.ps1')) {
    $rd = Join-Path $OutDir ('runs/recorder-' + $entry)
    $er = Join-Path $rd 'entry-run'
    $resultDir = if ($entry -eq 'p0_baseline.ps1') { Join-Path $er 'run-v3-local' } else { $er }
    New-Item -ItemType Directory -Path $resultDir -Force | Out-Null
    '{}' | Set-Content (Join-Path $resultDir 'result.json') -Encoding ASCII
    @{ entry = $entry; entry_run_dir = $er; actual_exit = 0 } | ConvertTo-Json | Set-Content (Join-Path $rd 'observed.json') -Encoding UTF8
    $found = @(Get-P0RecordedRuns $OutDir $entry)
    $checks += [pscustomobject]@{ check = $entry; passed = ($found.Count -eq 1 -and $found[0].FullName -eq $resultDir -and $found[0].P0Observation.actual_exit -eq 0) }
}
$badFile = Join-Path $OutDir 'runs/recorder-p0_probe_attribution.ps1/entry-run/result.json'
# Explicit test fixture only, owned by this invocation.
Remove-Item -LiteralPath $badFile
$rejected = $false
try { $null = @(Get-P0RecordedRuns $OutDir 'p0_probe_attribution.ps1') } catch { $rejected = $true }
$checks += [pscustomobject]@{ check = 'missing-result-rejected'; passed = $rejected }
foreach ($name in @('matrix-20261103-real','matrix-selftest-z','matrix-z-reuse-probe','matrix-partial')) {
    $dir = Join-Path $OutDir ('runs/' + $name)
    New-Item -ItemType Directory -Path (Join-Path $dir 'cases') -Force | Out-Null
    'case,expectedExit,actualExit,verdict,reason' | Set-Content (Join-Path $dir 'cases/matrix.csv') -Encoding ASCII
    @{ kind = $(if ($name -eq 'matrix-selftest-z') { 'selftest' } else { 'acceptance' }); only = $(if ($name -eq 'matrix-partial') { 'one' } else { '' }) } | ConvertTo-Json | Set-Content (Join-Path $dir 'matrix-identity.json') -Encoding UTF8
}
$mx = @(Get-P0MatrixRuns $OutDir)
$checks += [pscustomobject]@{ check = 'matrix-excludes-selftest-reuse-partial'; passed = ($mx.Count -eq 1 -and $mx[0].Name -eq 'matrix-20261103-real') }
$proof = Join-Path $OutDir 'path with space/recorder-baseline'
& (Join-Path $PSScriptRoot 'p0_run_recorder.ps1') -EntryScript (Join-Path $PSScriptRoot 'p0_baseline.ps1') -EntryArgs @('-PathOnly','-EvidenceRoot',$EvidenceRoot) -RecorderDir $proof
$observed = Get-Content (Join-Path $proof 'observed.json') -Raw | ConvertFrom-Json
$pathProof = Get-Content (Join-Path $proof 'entry-run/path-proof.json') -Raw | ConvertFrom-Json
$checks += [pscustomobject]@{ check = 'baseline-outdir-recorder-spaces'; passed = ($observed.actual_exit -eq 0 -and $observed.entry_run_dir_exists -and $pathProof.resolved_base -eq $observed.entry_run_dir) }
# Refuse an existing empty output before package discovery or any writes.
foreach ($entry in @('p0_probe_attribution.ps1','p0_probe_perprocess.ps1')) {
    $target = Join-Path $OutDir ('reuse-' + $entry)
    New-Item -ItemType Directory -Path $target | Out-Null
    $argv = @('-NoProfile','-File',(Join-Path $PSScriptRoot $entry),'-OutDir',$target)
    $proc = Start-P0PowerShell -ArgumentList (($argv | ForEach-Object { ConvertTo-P0Argument $_ }) -join ' ') -Wait -RedirectStandardOutput ($target + '.stdout.txt') -RedirectStandardError ($target + '.stderr.txt')
    $checks += [pscustomobject]@{ check = ($entry + '-empty-reuse'); passed = ($proc.ExitCode -eq 2 -and @(Get-ChildItem $target -Force).Count -eq 0) }
}
$checks | ConvertTo-Json | Set-Content (Join-Path $OutDir 'checks.json') -Encoding UTF8
$hashes = @{}
foreach ($file in @('p0_routing_negtest.ps1','p0_paths.ps1','p0_runs.ps1','p0_run_recorder.ps1','p0_baseline.ps1','p0_probe_attribution.ps1','p0_probe_perprocess.ps1')) { $hashes[$file] = (Get-FileHash (Join-Path $PSScriptRoot $file) -Algorithm SHA256).Hash }
$hashes | ConvertTo-Json | Set-Content (Join-Path $OutDir 'script-hashes.json') -Encoding UTF8
$checks | Format-Table
if (@($checks | Where-Object { -not $_.passed }).Count) { exit 1 }
exit 0
