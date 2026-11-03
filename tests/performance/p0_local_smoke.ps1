# Reproducible pure-local remediation checks. NOT a P0/backend acceptance pass.
param(
    [string]$RepoRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent),
    [string]$EvidenceRoot = '', [string]$PythonExe = ''
)
. (Join-Path $PSScriptRoot 'p0_paths.ps1')
$ErrorActionPreference = 'Stop'
$EvidenceRoot = Resolve-P0EvidenceRoot $RepoRoot $EvidenceRoot
if (Test-Path -LiteralPath $EvidenceRoot) { throw 'round exists; refuse overwrite' }
New-Item -ItemType Directory -Path (Join-Path $EvidenceRoot 'runs') -Force | Out-Null
Copy-Item (Join-Path $RepoRoot 'docs/specifications/native-desktop/p0-reference/CASE_MANIFEST.json') (Join-Path $EvidenceRoot 'CASE_MANIFEST.json')
$python = Resolve-P0Python (Join-Path $RepoRoot '.local/runtime') $PythonExe
$rows = @()
function Run-Local([string]$Name, [string]$Entry, [string[]]$EntryArgs, [int]$ExpectedExit = 0) {
    $dir = Join-Path $EvidenceRoot ('runs/' + $Name)
    New-Item -ItemType Directory -Path $dir | Out-Null
    $argv = @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot $Entry)) + $EntryArgs
    $started = (Get-Date).ToString('o')
    $child = Start-P0PowerShell -ArgumentList (($argv | ForEach-Object { ConvertTo-P0Argument $_ }) -join ' ') -RedirectStandardOutput (Join-Path $dir 'stdout.txt') -RedirectStandardError (Join-Path $dir 'stderr.txt')
    $identity = @{ pid = $child.Id; start_time = $child.StartTime.ToString('o') }
    if (-not $child.WaitForExit(300000)) { $child.Kill(); throw ('timeout: ' + $Name) }
    $child.Refresh()
    $stderrEmpty = (Get-Item (Join-Path $dir 'stderr.txt')).Length -eq 0
    $script:rows += [pscustomobject]@{ check = $Name; expected_exit = $ExpectedExit; observed_exit = $child.ExitCode; stderr_empty = $stderrEmpty; passed = ($child.ExitCode -eq $ExpectedExit -and $stderrEmpty); child_identity = $identity; started = $started; ended = (Get-Date).ToString('o'); argument_vector = $argv; script_sha256 = (Get-FileHash (Join-Path $PSScriptRoot $Entry) -Algorithm SHA256).Hash; cleanup = 'child exited, owned fixtures retained' }
}
Run-Local 'recovery' 'p0_recovery_negtest.ps1' @('-EvidenceRoot',$EvidenceRoot,'-OutDir',(Join-Path $EvidenceRoot 'runs/recovery-proof'),'-PythonExe',$python)
Run-Local 'asset-manifest' 'p0_asset_manifest_negtest.ps1' @('-EvidenceRoot',$EvidenceRoot,'-PythonExe',$python)
Run-Local 'routing' 'p0_routing_negtest.ps1' @('-EvidenceRoot',$EvidenceRoot)
Run-Local 'seal-twopass' 'p0_seal_negtest.ps1' @('-OutDir',(Join-Path $EvidenceRoot 'seal-fixtures'))
Run-Local 'loopback' 'p0_loopback_negtest.ps1' @('-EvidenceRoot',$EvidenceRoot,'-PythonExe',$python)
Run-Local 'environment' 'p0_env_negtest.ps1' @('-EvidenceRoot',$EvidenceRoot)
Run-Local 'matrix-engine' 'p0_negative_tests.ps1' @('-EvidenceRoot',$EvidenceRoot,'-SelfTest','-RunId','selftest-local-current','-PythonExe',$python)
$scratch = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) ('Temp/p0-checker-' + [guid]::NewGuid().ToString('N'))
Run-Local 'checker-engine' 'p0_evidence_check.ps1' @('-SelfTest','-SelfTestOut',$scratch,'-ReportPath',(Join-Path $EvidenceRoot 'checker-selftest-report.json'))
Run-Local 'incomplete-gate-rejected' 'p0_evidence_check.ps1' @('-EvidenceRoot',$EvidenceRoot,'-ReportPath',(Join-Path $EvidenceRoot 'incomplete-gate-report.json')) 1
$hashes = @{}
Get-ChildItem $PSScriptRoot -Recurse -File | Where-Object Extension -in @('.ps1','.py') | ForEach-Object { $hashes[$_.FullName.Substring($PSScriptRoot.Length + 1)] = (Get-FileHash $_.FullName -Algorithm SHA256).Hash }
$hashes | ConvertTo-Json | Set-Content (Join-Path $EvidenceRoot 'script-hashes.json') -Encoding UTF8
@{ scope = 'local-remediation-only'; p0_gate = 'BLOCKED'; backend = 'unverified: locked runtime/packages/assets unavailable'; baseline = 'ab5d684df52aa1ec760eb25bc777932003b984b7'; python = $python; checks = $rows } | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $EvidenceRoot 'LOCAL_RESULTS.json') -Encoding UTF8
$rows | Format-Table check,expected_exit,observed_exit,stderr_empty,passed
if (@($rows | Where-Object { -not $_.passed }).Count) { exit 1 }
exit 0
