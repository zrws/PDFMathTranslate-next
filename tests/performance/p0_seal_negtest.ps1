# Two-pass digest regression on explicitly synthetic fixtures; no frozen PASS.
param([string]$RepoRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent), [string]$OutDir = '')
. (Join-Path $PSScriptRoot 'p0_paths.ps1')
$ErrorActionPreference = 'Stop'
if (-not $OutDir) { $OutDir = Join-Path $RepoRoot ('docs/verification/native-desktop/seal-selftest-' + [guid]::NewGuid().ToString('N')) }
if (Test-Path $OutDir) { throw 'output exists' }
$fixture = Join-Path $OutDir 'synthetic'
$gt = Join-Path $fixture 'runs/guard-test-synthetic'
New-Item -ItemType Directory -Path $gt -Force | Out-Null
'{"cases":[],"new_cases_this_round":[],"note":"synthetic digest regression only"}' | Set-Content (Join-Path $fixture 'CASE_MANIFEST.json') -Encoding ASCII
'{}' | Set-Content (Join-Path $fixture 'CHANGE_IMPACT.json') -Encoding ASCII
'synthetic only' | Set-Content (Join-Path $fixture 'PLAN.md') -Encoding ASCII
'{"normal":{"exitCode":0},"no_guard":{"exitCode":1,"passed":true},"partial":{"exitCode":1,"passed":true}}' | Set-Content (Join-Path $gt 'summary.json') -Encoding ASCII
foreach ($mode in @('normal','no_guard','partial')) {
    New-Item -ItemType Directory -Path (Join-Path $gt $mode) | Out-Null
    '{}' | Set-Content (Join-Path $gt ($mode + '/testResults.json')) -Encoding ASCII
}
$results = @()
foreach ($pass in @(1,2)) {
    $argv = @('-NoProfile','-File',(Join-Path $PSScriptRoot 'p0_seal_round.ps1'),'-RepoRoot',$RepoRoot,'-EvidenceRoot',$fixture)
    $child = Start-P0PowerShell -ArgumentList (($argv | ForEach-Object { ConvertTo-P0Argument $_ }) -join ' ') -Wait -RedirectStandardOutput (Join-Path $OutDir ('pass-' + $pass + '.stdout.txt')) -RedirectStandardError (Join-Path $OutDir ('pass-' + $pass + '.stderr.txt'))
    $manifest = Get-Content (Join-Path $fixture 'INPUT_MANIFEST.json') -Raw | ConvertFrom-Json
    $drift = @($manifest.entries | Where-Object { (Get-FileHash (Join-Path $fixture $_.path) -Algorithm SHA256).Hash -ne $_.sha256 })
    $stream = ($manifest.entries | ForEach-Object { "$($_.path)`0$($_.sha256)`n" }) -join ''
    $sha = [Security.Cryptography.SHA256]::Create()
    $digest = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($stream))).Replace('-','')
    $results += @{ pass = $pass; observed_exit = $child.ExitCode; no_drift = ($drift.Count -eq 0); index_included = (@($manifest.entries | Where-Object path -eq 'INDEX.md').Count -eq 1); self_excluded = (@($manifest.entries | Where-Object path -eq 'INPUT_MANIFEST.json').Count -eq 0); digest_matches = ($digest -eq $manifest.digest) }
}
$results | ConvertTo-Json | Set-Content (Join-Path $OutDir 'results.json') -Encoding UTF8
@{ 'p0_seal_round.ps1' = (Get-FileHash (Join-Path $PSScriptRoot 'p0_seal_round.ps1') -Algorithm SHA256).Hash; 'p0_seal_negtest.ps1' = (Get-FileHash $PSCommandPath -Algorithm SHA256).Hash } | ConvertTo-Json | Set-Content (Join-Path $OutDir 'script-hashes.json') -Encoding UTF8
$results | ForEach-Object { [pscustomobject]$_ } | Format-Table
if (@($results | Where-Object { $_.observed_exit -ne 0 -or -not $_.no_drift -or -not $_.index_included -or -not $_.self_excluded -or -not $_.digest_matches }).Count) { exit 1 }
exit 0
