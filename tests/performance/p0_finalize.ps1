#requires -Version 7.0
# Resume post-processing only. Never reruns or edits raw safety observations.
param([Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)][string]$EvidenceRoot)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'p0_paths.ps1')
if (-not (Test-Path (Join-Path $EvidenceRoot 'runs/checker-selftest-report.json'))) { throw 'completed preflight/matrix/selftest evidence required' }
if (Test-Path (Join-Path $EvidenceRoot 'runs/checker-prior-pass/report.json')) { throw 'prior checker report exists; refuse replacement' }
$runId = 'finalize-' + [guid]::NewGuid().ToString('N')
$hostExe = (Get-Process -Id $PID).Path
$sourceCopy = Join-Path $EvidenceRoot ('runs/' + $runId + '/source.ps1')
New-Item -ItemType Directory -Path (Split-Path $sourceCopy) | Out-Null
Copy-Item -LiteralPath $PSCommandPath -Destination $sourceCopy
@{ mode='post-processing only'; host_version=$PSVersionTable.PSVersion.ToString(); host=$hostExe; source_sha256=(Get-FileHash $PSCommandPath).Hash; source_copy=$sourceCopy; preceding_failure='reports/seal-1-derive.observed.json and stderr preserved; mixed PowerShell UTF-8 decoding, not a successful overall acceptance driver'; raw_observations_modified=$false } | ConvertTo-Json | Set-Content (Join-Path $EvidenceRoot 'FINALIZATION.json') -Encoding utf8
function Run([string]$Name,[string]$Entry,[string[]]$Arguments_) {
    $entryPath=Join-Path $PSScriptRoot $Entry
    $argv=@('-NoProfile','-File',$entryPath,'-RepoRoot',$RepoRoot,'-EvidenceRoot',$EvidenceRoot)+$Arguments_
    $prefix=Join-Path $EvidenceRoot ('reports/'+$runId+'-'+$Name)
    $p=Start-Process -FilePath $hostExe -ArgumentList (($argv|ForEach-Object {ConvertTo-P0Argument $_}) -join ' ') -PassThru -NoNewWindow -RedirectStandardOutput ($prefix+'.stdout.txt') -RedirectStandardError ($prefix+'.stderr.txt')
    $null=$p.Handle
    $start=$p.StartTime.ToString('o'); $childId=$p.Id
    $timeout=-not $p.WaitForExit(600000)
    if ($timeout -and -not $p.HasExited) { $p.Kill($true); [void]$p.WaitForExit(10000) }
    $p.Refresh()
    $record=@{ entry=$entryPath; command=$hostExe+' '+(($argv|ForEach-Object {ConvertTo-P0Argument $_}) -join ' '); argument_vector=$argv; child_pid=$childId; started_at=$start; actual_exit=$(if($timeout){'timeout'}else{$p.ExitCode}); timeout_hit=$timeout; process_exited=$p.HasExited; powershell_version=$PSVersionTable.PSVersion.ToString() }
    $record|ConvertTo-Json -Depth 5|Set-Content ($prefix+'.observed.json') -Encoding utf8
    if($timeout -or $p.ExitCode -ne 0){ throw ('post-processing failed; preserve all records: '+$Name) }
    Write-Host ($Name+': actual exit '+$p.ExitCode)
    return $record
}
function Seal([string]$Label) {
    $null=Run ($Label+'-derive') 'p0_seal_round.ps1' @()
    $coverage=Get-Content (Join-Path $EvidenceRoot 'COVERAGE.json') -Raw -Encoding UTF8|ConvertFrom-Json
    @{requirements=$coverage.coverage; policy='machine-derived current observations; no historical pass inherited'}|ConvertTo-Json -Depth 7|Set-Content (Join-Path $EvidenceRoot 'REQUIREMENTS.json') -Encoding utf8
    $null=Run ($Label+'-bind') 'p0_seal_round.ps1' @()
}
Seal 'first'
$prior=Join-Path $EvidenceRoot 'runs/checker-prior-pass/report.json'
$observed=Run 'checker-first' 'p0_evidence_check.ps1' @('-ReportPath',$prior)
$observed.report_sha256=(Get-FileHash $prior).Hash
$observed|ConvertTo-Json -Depth 5|Set-Content (Join-Path $EvidenceRoot 'runs/checker-prior-pass/observed.json') -Encoding utf8
Copy-Item $prior (Join-Path $EvidenceRoot 'EVIDENCE_CHECK.json')
Seal 'final'
$final=Join-Path $EvidenceRoot 'reports/checker-final.json'
$observed=Run 'checker-final' 'p0_evidence_check.ps1' @('-ReportPath',$final,'-Final')
Copy-Item $final (Join-Path $EvidenceRoot 'EVIDENCE_CHECK.json') -Force
$observed|ConvertTo-Json -Depth 5|Set-Content (Join-Path $EvidenceRoot 'reports/checker-final.observed.json') -Encoding utf8
Write-Host ('Final checker actual exit 0; independent review required: '+$EvidenceRoot)
exit 0
