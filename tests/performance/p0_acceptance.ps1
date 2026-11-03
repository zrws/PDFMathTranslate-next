# Full frozen P0 acceptance. Requires pre-staged offline runtime/assets and
# independent preflight approval; never downloads or submits a translation.
param(
    [string]$RepoRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent),
    [Parameter(Mandatory)][string]$InstallRoot,
    [Parameter(Mandatory)][string]$PythonExe,
    [string]$EvidenceRoot = ''
)
. (Join-Path $PSScriptRoot 'p0_paths.ps1')
$ErrorActionPreference = 'Stop'
$EvidenceRoot = Resolve-P0EvidenceRoot $RepoRoot $EvidenceRoot
if (Test-Path -LiteralPath $EvidenceRoot) { throw 'acceptance root exists; refuse reuse' }
New-Item -ItemType Directory -Path (Join-Path $EvidenceRoot 'runs/checker-prior-pass'),(Join-Path $EvidenceRoot 'reports') -Force | Out-Null
Copy-Item (Join-Path $RepoRoot 'docs/specifications/native-desktop/p0-reference/CASE_MANIFEST.json') $EvidenceRoot
$manifest = Get-Content (Join-Path $EvidenceRoot 'CASE_MANIFEST.json') -Raw|ConvertFrom-Json
$impact = @($manifest.cases)+@($manifest.new_cases_this_round)|ForEach-Object { @{ case=$_.id; expected_exit=$_.expected_exit; expected_reason=$_.expected_reason; status='unverified-before-execution'; historical_evidence='unavailable, never inherited'; mode='new-run' } }
@{ round=(Split-Path $EvidenceRoot -Leaf); baseline=(& git -C $RepoRoot rev-parse HEAD); runtime=$InstallRoot; python=$PythonExe; cases=$impact; driver_sha256=(Get-FileHash $PSCommandPath -Algorithm SHA256).Hash }|ConvertTo-Json -Depth 6|Set-Content (Join-Path $EvidenceRoot 'CHANGE_IMPACT.json') -Encoding UTF8
'Frozen 24+4 cases unchanged. Pure-local preflights, then recorder-owned backend smoke/import/recovery/pytest, then full negative matrix; no translation/download/user cache access. Two checker passes: M01/M02 explicit N/A in first pass, final requires that pass, its actual exit, identity and report hash. All failures preserved; root reuse refused.'|Set-Content (Join-Path $EvidenceRoot 'PLAN.md') -Encoding UTF8
'{"state":"pending","requirements":[]}'|Set-Content (Join-Path $EvidenceRoot 'REQUIREMENTS.json') -Encoding UTF8
$common = @('-RepoRoot',$RepoRoot,'-InstallRoot',$InstallRoot,'-PythonExe',$PythonExe,'-EvidenceRoot',$EvidenceRoot)
function Driver([string]$Name,[string]$Entry,[string[]]$Args_) {
    $argv=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot $Entry))+$Args_
    $prefix=Join-Path $EvidenceRoot ('reports/'+$Name)
    $p=Start-P0PowerShell -ArgumentList (($argv|ForEach-Object{ConvertTo-P0Argument $_}) -join ' ') -RedirectStandardOutput ($prefix+'.stdout.txt') -RedirectStandardError ($prefix+'.stderr.txt')
    $started=$p.StartTime.ToString('o'); $pid_=$p.Id
    if (-not $p.WaitForExit(1800000)) { $p.Kill(); throw ('driver timed out: '+$Name) }
    $p.Refresh()
    @{ entry=(Join-Path $PSScriptRoot $Entry); argument_vector=$argv; child_pid=$pid_; started_at=$started; actual_exit=$p.ExitCode; timeout_hit=$false }|ConvertTo-Json -Depth 4|Set-Content ($prefix+'.observed.json') -Encoding UTF8
    Write-Host ($Name+': actual exit '+$p.ExitCode)
    if ($p.ExitCode -ne 0) { throw ('acceptance driver failed; preserve root: '+$Name) }
}
function Recorded([string]$Name,[string]$Entry,[string[]]$Extra,[int]$Expected=0) {
    $dir=Join-Path $EvidenceRoot ('runs/recorder-'+$Name)
    & (Join-Path $PSScriptRoot 'p0_run_recorder.ps1') -EntryScript (Join-Path $PSScriptRoot $Entry) -EntryArgs ($common+$Extra) -RecorderDir $dir -RepoRoot $RepoRoot -TimeoutMinutes 30
    $o=Get-Content (Join-Path $dir 'observed.json') -Raw|ConvertFrom-Json
    if ("$($o.actual_exit)" -ne "$Expected" -or -not $o.entry_run_dir_exists) { throw ('recorded entry failed: '+$Name) }
}
foreach ($pair in @(@('guard','p0_c1_guard_test.ps1'),@('entrygate','p0_entry_gate_negtest.ps1'),@('mutations','p0_guard_mutations.ps1'),@('empty-host','p0_empty_host_case.ps1'),@('loopback','p0_loopback_negtest.ps1'),@('isolation','p0_isolation_negtest.ps1'),@('assets','p0_asset_manifest_negtest.ps1'),@('recovery','p0_recovery_negtest.ps1'))) { Driver $pair[0] $pair[1] $common }
Driver 'environment' 'p0_env_negtest.ps1' @('-RepoRoot',$RepoRoot,'-EvidenceRoot',$EvidenceRoot)
Recorded 'perprocess' 'p0_probe_perprocess.ps1' @('-SampleSeconds','6')
Recorded 'perprocess-n04' 'p0_probe_perprocess.ps1' @('-SampleSeconds','6','-FailInject','midrun-exception') 1
Recorded 'attribution' 'p0_probe_attribution.ps1' @()
Recorded 'attribution-fail' 'p0_probe_attribution.ps1' @('-FailInject','import-fail') 1
Recorded 'baseline' 'p0_baseline.ps1' @('-IdleSeconds','5','-StartupRuns','1')
Driver 'pytest' 'p0_pytest_isolated.ps1' $common
Recorded 'matrix' 'p0_negative_tests.ps1' @()
$scratch=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) ('Temp/p0-checker-final-'+[guid]::NewGuid().ToString('N'))
Driver 'checker-selftest' 'p0_evidence_check.ps1' @('-RepoRoot',$RepoRoot,'-SelfTest','-SelfTestOut',$scratch,'-ReportPath',(Join-Path $EvidenceRoot 'runs/checker-selftest-report.json'))
foreach ($log in (Get-ChildItem $EvidenceRoot -Recurse -Filter '*.log' -File)) { $copy=$log.FullName+'.txt'; if (Test-Path $copy) { if ((Get-FileHash $copy).Hash -ne (Get-FileHash $log.FullName).Hash) { throw 'existing log copy differs' } } else { Copy-Item $log.FullName $copy } }
$script:sealPass = 0
function Seal {
    $script:sealPass++
    Driver ('seal-'+$script:sealPass+'-derive') 'p0_seal_round.ps1' @('-RepoRoot',$RepoRoot,'-EvidenceRoot',$EvidenceRoot)
    $cov=Get-Content (Join-Path $EvidenceRoot 'COVERAGE.json') -Raw|ConvertFrom-Json
    @{ requirements=$cov.coverage; policy='machine-derived current evidence only; no historical pass inherited' }|ConvertTo-Json -Depth 7|Set-Content (Join-Path $EvidenceRoot 'REQUIREMENTS.json') -Encoding UTF8
    Driver ('seal-'+$script:sealPass+'-bind') 'p0_seal_round.ps1' @('-RepoRoot',$RepoRoot,'-EvidenceRoot',$EvidenceRoot)
}
Seal
$prior=Join-Path $EvidenceRoot 'runs/checker-prior-pass/report.json'
Driver 'checker-first' 'p0_evidence_check.ps1' @('-RepoRoot',$RepoRoot,'-EvidenceRoot',$EvidenceRoot,'-ReportPath',$prior)
$outer=Get-Content (Join-Path $EvidenceRoot 'reports/checker-first.observed.json') -Raw|ConvertFrom-Json
$outer|Add-Member -NotePropertyName command -NotePropertyValue ('powershell.exe '+(($outer.argument_vector|ForEach-Object{ConvertTo-P0Argument $_}) -join ' '))
$outer|Add-Member -NotePropertyName report_sha256 -NotePropertyValue (Get-FileHash $prior -Algorithm SHA256).Hash
$outer|ConvertTo-Json -Depth 5|Set-Content (Join-Path $EvidenceRoot 'runs/checker-prior-pass/observed.json') -Encoding UTF8
Copy-Item $prior (Join-Path $EvidenceRoot 'EVIDENCE_CHECK.json')
Seal
$final=Join-Path $EvidenceRoot 'reports/checker-final.json'
Driver 'checker-final' 'p0_evidence_check.ps1' @('-RepoRoot',$RepoRoot,'-EvidenceRoot',$EvidenceRoot,'-ReportPath',$final,'-Final')
Copy-Item $final (Join-Path $EvidenceRoot 'EVIDENCE_CHECK.json') -Force
Write-Host ('P0 final checker exit 0; independent final review still required: '+$EvidenceRoot)
exit 0
