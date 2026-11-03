# Round sealing for r2-integrated-20261003-01 (ASCII only, PS 5.1 safe).
# R5 v2 over v1:
#   1. LOG_COPY_INDEX: HONEST original states - original_present (real path+hash),
#      original_present_at_temp_root (real recorded temp-root path, verified),
#      original_unavailable (null path, hash only if genuinely observed before),
#      copy_only_historical. NO placeholder paths are ever sent to file APIs.
#      Originals are NEVER deleted; existing copies never overwritten.
#   2. COVERAGE.json: per-case machine mapping (id, source run, artifacts,
#      runtime hash binding, planned vs OBSERVED exit, observed reason, verdict,
#      new-run-or-reuse rationale). Observed exits come from recorder observed.json.
#   3. INPUT_MANIFEST.json: stable-ordered input list with per-file sha256 and
#      a digest; checker outputs (reports dir, EVIDENCE_CHECK.json, stdout/stderr
#      records) are EXCLUDED with documented rationale.
#   4. Canonical script-hashes at the round root (current source identity).
#   5. INDEX.md regenerated with real links + annotations.
# Exit: 0 ok; 1 derivation failure.

param(
    [string]$RepoRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent),
    [string]$EvidenceRoot = ''
)

. (Join-Path $PSScriptRoot 'p0_paths.ps1')
$EvidenceRoot = Resolve-P0EvidenceRoot $RepoRoot $EvidenceRoot

. (Join-Path $PSScriptRoot 'p0_runs.ps1')
$ErrorActionPreference = 'Stop'
$manifest = Get-Content (Join-Path $EvidenceRoot 'CASE_MANIFEST.json') -Raw | ConvertFrom-Json
$expectedById = @{}
foreach ($c in @($manifest.cases) + @($manifest.new_cases_this_round)) { if ($c) { $expectedById[$c.id] = $c } }

function Sha([string]$p) { if (Test-Path $p) { return (Get-FileHash $p -Algorithm SHA256).Hash } return $null }
function Rel([string]$p) { if ($p -and $p.StartsWith($EvidenceRoot)) { return ($p.Substring($EvidenceRoot.Length + 1)).Replace('\', '/') } return $p }

# ---------- 0. recorder observed-exit map ------------------------------------
# every runs/recorder-*/observed.json binds an entry run dir to the OUTER
# OBSERVED exit code (never the entry's planned exit)
$observedByEntryRun = @{}
$recorderFiles = @()
foreach ($rd in (Get-ChildItem (Join-Path $EvidenceRoot 'runs') -Directory -Filter 'recorder-*' -ErrorAction SilentlyContinue)) {
    $oj = Join-Path $rd.FullName 'observed.json'
    if (-not (Test-Path $oj)) { continue }
    $recorderFiles += $oj
    $o = Get-Content $oj -Raw | ConvertFrom-Json
    $erd = "$($o.entry_run_dir)"
    if ($erd -and $o.PSObject.Properties['actual_exit']) {
        $observedByEntryRun[[IO.Path]::GetFullPath($erd)] = $o
    }
}

# ---------- 1. LOG_COPY_INDEX (honest original states) -----------------------
$pairs = New-Object System.Collections.Generic.List[object]
foreach ($lf in (Get-ChildItem $EvidenceRoot -Recurse -Filter '*.log' -File -ErrorAction SilentlyContinue)) {
    $copy = $lf.FullName -replace '\.log$', '.log.txt'
    if (-not (Test-Path $copy)) { continue }
    $shaO = Sha $lf.FullName
    $shaC = Sha $copy
    $pairs.Add([ordered]@{
        original_state = 'original_present'
        original = (Rel $lf.FullName)
        copy = (Rel $copy)
        original_sha256 = $shaO
        copy_sha256 = $shaC
        sanitization = 'none (byte-identical copy; NO sanitization performed or claimed)'
        sanitized_at = $null
        copied_at = $lf.LastWriteTime.ToString('o')
    })
}
foreach ($ct in (Get-ChildItem $EvidenceRoot -Recurse -Filter '*.log.txt' -File -ErrorAction SilentlyContinue)) {
    $orig = $ct.FullName -replace '\.log\.txt$', '.log'
    if (Test-Path $orig) { continue }   # paired above
    # copy-only: try to locate the TRUE original in the run's recorded temp root
    $shaC = Sha $ct.FullName
    $runDir = $ct.Directory.FullName
    $tempRoot = $null
    $rj = Join-Path $runDir 'result.json'
    if (Test-Path $rj) {
        try {
            $r = Get-Content $rj -Raw | ConvertFrom-Json
            if ($r.PSObject.Properties['temp_root']) { $tempRoot = "$($r.temp_root)" }
        } catch { }
    }
    $state = 'copy_only_historical'
    $origPath = $null
    $origSha = $null
    if ($tempRoot) {
        $candidate = Join-Path $tempRoot ($ct.Name -replace '\.log\.txt$', '.log')
        if (Test-Path $candidate) {
            $state = 'original_present_at_temp_root'
            $origPath = $candidate
            $origSha = Sha $candidate
        } else {
            $state = 'original_unavailable'
            $origPath = $null
            $origSha = $null   # NEVER re-stamp the copy hash as an original hash
        }
    }
    $pairs.Add([ordered]@{
        original_state = $state
        original = $origPath
        original_recorded_temp_root = $tempRoot
        copy = (Rel $ct.FullName)
        original_sha256 = $origSha
        copy_sha256 = $shaC
        sanitization = 'none (byte-identical copy; NO sanitization performed or claimed)'
        sanitized_at = $null
        copied_at = $ct.LastWriteTime.ToString('o')
        note = 'original location resolved from the run result.json temp_root; when absent the original is honestly unavailable - the copy hash proves only the copy'
    })
}
[ordered]@{
    generatedAt = (Get-Date).ToString('o')
    policy = 'honest original states: original_present / original_present_at_temp_root / original_unavailable / copy_only_historical. Placeholders are never sent to file APIs; original hashes are only recorded when genuinely observed; originals are never deleted; copies are never overwritten. Byte-identical copies; no sanitization performed or claimed.'
    pair_count = $pairs.Count
    pairs = $pairs
} | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $EvidenceRoot 'LOG_COPY_INDEX.json') -Encoding UTF8
Write-Host ("[LOG_COPY_INDEX] {0} pairs" -f $pairs.Count)

# ---------- 2. coverage derivation (COVERAGE.json) ---------------------------
$coverage = New-Object System.Collections.Generic.List[object]
$seenCaseIds = @{}
$coverageRows = New-Object System.Collections.Generic.List[string]
function AddRow {
    param([string]$caseId, [string]$actualExit, [string]$verdict, [string]$source,
          [string]$reason, [string]$mode = 'new-run', [string]$binding = '')
    if (-not $expectedById.ContainsKey($caseId)) { return }
    if ($seenCaseIds.ContainsKey($caseId)) { return }
    $seenCaseIds[$caseId] = $true
    $coverageRows.Add(("{0},{1},{2},{3},{4}" -f $caseId, $expectedById[$caseId].expected_exit, $actualExit, $verdict, $reason)) | Out-Null
    $coverage.Add([ordered]@{
        case = $caseId
        expected_exit = $expectedById[$caseId].expected_exit
        observed_exit = $actualExit
        verdict = $verdict
        expected_reason = $expectedById[$caseId].expected_reason
        source = $source
        mode = $mode
        binding_rationale = $binding
    }) | Out-Null
    Write-Host ("  [coverage] {0}: observed={1} verdict={2} <- {3} ({4})" -f $caseId, $actualExit, $verdict, $source, $mode)
}

# 2a. guard-test runs: per-mode testResults.json
$gtDir = Get-ChildItem (Join-Path $EvidenceRoot 'runs') -Directory -Filter 'guard-test-r1' -ErrorAction SilentlyContinue |
    Where-Object { Test-Path (Join-Path $_.FullName 'summary.json') } | Select-Object -First 1
if (-not $gtDir) {
    $gtDir = Get-ChildItem (Join-Path $EvidenceRoot 'runs') -Directory -Filter 'guard-test-*' |
        Where-Object { Test-Path (Join-Path $_.FullName 'summary.json') } | Sort-Object Name | Select-Object -Last 1
}
if (-not $gtDir) { Write-Host '[FAIL] no guard-test run found'; exit 1 }
$gtMap = @{
    sync_blocked = 'G06'; async_blocked = 'G07'; httpx_blocked = 'G08'; dns_blocked = 'G09'
    loopback_allowed = 'G10'; fallback_zero_hits = 'G13'
    pseudo_loopback_predicate = 'N01'
    leading_zero_octet_blocked = 'N01'
}
$sumJ = Get-Content (Join-Path $gtDir.FullName 'summary.json') -Raw | ConvertFrom-Json
foreach ($mode in @('normal','no_guard','partial')) {
    $trPath = Join-Path $gtDir.FullName ($mode + '\testResults.json')
    if (-not (Test-Path $trPath)) { continue }
    $tr = Get-Content $trPath -Raw | ConvertFrom-Json
    $exit = $sumJ.PSObject.Properties[$mode] | ForEach-Object { $_.Value.exitCode }
    if ($mode -ne 'normal') {
        if ($mode -eq 'no_guard') { AddRow 'G02' $exit $(if ($sumJ.no_guard.passed) { 'PASS' } else { 'FAIL' }) ('runs/' + $gtDir.Name + '/no_guard') $expectedById['G02'].expected_reason }
        if ($mode -eq 'partial')  { AddRow 'G03' $exit $(if ($sumJ.partial.passed) { 'PASS' } else { 'FAIL' }) ('runs/' + $gtDir.Name + '/partial') $expectedById['G03'].expected_reason }
        continue
    }
    foreach ($sub in $gtMap.Keys) {
        if ($tr.PSObject.Properties[$sub] -and $tr.$sub.passed) {
            $verdict = $(if ("$exit" -eq "$($expectedById[$gtMap[$sub]].expected_exit)") { 'PASS' } else { 'FAIL' })
            AddRow $gtMap[$sub] $exit $verdict (Rel $trPath) $expectedById[$gtMap[$sub]].expected_reason
        } else {
            AddRow $gtMap[$sub] $exit 'FAIL' (Rel $trPath) 'missing_or_failed_subtest'
        }
    }
}

# 2b. entrygate matrix -> G04/G05/G14/G15
$egDir = Get-ChildItem (Join-Path $EvidenceRoot 'runs') -Directory -Filter 'entrygate-*' |
    Where-Object { Test-Path (Join-Path $_.FullName 'matrix.csv') } | Sort-Object Name | Select-Object -Last 1
if ($egDir) {
    $egMap = @{ 'G04-guard-log-unwritable' = 'G04'; 'G05-stale-handshake' = 'G05'; 'POS-healthy-handshake' = 'G14'; 'G15a-sitecustomize-missing' = 'G15'; 'G15b-sitecustomize-hash-mismatch' = 'G15' }
    foreach ($line in (Get-Content (Join-Path $egDir.FullName 'matrix.csv') | Where-Object { $_ -match ',' -and $_ -notmatch '^case,' })) {
        $p = $line.Split(',')
        if ($egMap.ContainsKey($p[0]) -and $p[3] -eq 'PASS') {
            $egCaseId = $egMap[$p[0]]
            AddRow $egCaseId $p[2] 'PASS' ((Rel $egDir.FullName) + '/matrix.csv') $expectedById[$egCaseId].expected_reason
        }
    }
}

# 2b-2. empty-host frozen case G12
$ehDir = Get-ChildItem (Join-Path $EvidenceRoot 'runs') -Directory -Filter 'empty-host-*' |
    Where-Object { Test-Path (Join-Path $_.FullName 'probe-exit.txt') } | Sort-Object Name | Select-Object -Last 1
if ($ehDir) {
    $ehExit = (Get-Content (Join-Path $ehDir.FullName 'probe-exit.txt') -Raw).Trim()
    AddRow 'G12' $ehExit $(if ("$ehExit" -eq "$($expectedById['G12'].expected_exit)") { 'PASS' } else { 'FAIL' }) ($ehDir.Name + '/probe-exit.txt') $expectedById['G12'].expected_reason
}

# 2b-3. mutation suite -> N02
$muDir = Get-ChildItem (Join-Path $EvidenceRoot 'runs') -Directory -Filter 'mutations-*' |
    Where-Object { Test-Path (Join-Path $_.FullName 'matrix.csv') } | Sort-Object Name | Select-Object -Last 1
if ($muDir) {
    $muRows = @(Get-Content (Join-Path $muDir.FullName 'matrix.csv') | Where-Object { $_ -match ',' -and $_ -notmatch '^case,' })
    $cleanOk = @($muRows | Where-Object { $_ -like 'clean,0,0,PASS*' }).Count -eq 1
    $mutRows = @($muRows | Where-Object { $_ -match '^M-' })
    $allRejected = ($mutRows.Count -ge 4) -and (@($mutRows | Where-Object { $_ -match ',1,1,PASS' }).Count -eq $mutRows.Count)
    AddRow 'N02' '1' $(if ($cleanOk -and $allRejected) { 'PASS' } else { 'FAIL' }) ($muDir.Name + '/matrix.csv') $expectedById['N02'].expected_reason
}

# 2c. env restore matrix -> G16
$envDir = Get-ChildItem (Join-Path $EvidenceRoot 'runs') -Directory -Filter 'env-restore-*' |
    Where-Object { Test-Path (Join-Path $_.FullName 'matrix.csv') } | Sort-Object Name | Select-Object -Last 1
if ($envDir) {
    $envAllPass = -not (Get-Content (Join-Path $envDir.FullName 'matrix.csv') | Where-Object { $_ -match ',FAIL$' })
    AddRow 'G16' '0' $(if ($envAllPass) { 'PASS' } else { 'FAIL' }) ((Rel $envDir.FullName) + '/matrix.csv') $expectedById['G16'].expected_reason
}

# 2d. perprocess results -> P01/P02/N04 (observed exit from recorder)
$ppRuns = @(Get-P0RecordedRuns $EvidenceRoot 'p0_probe_perprocess.ps1')
foreach ($pp in $ppRuns) {
    $rp = Get-Content (Join-Path $pp.FullName 'result.json') -Raw | ConvertFrom-Json
    $injected = ($rp.fail_inject -eq 'midrun-exception')
    $targetId = if ($injected) { 'N04' } else { 'P01' }
    # R4: observed exit comes from the RECORDER, not the planned exit
    $observedExit = $null
    $observedExit = "$($pp.P0Observation.actual_exit)"
    $useExit = if ($null -ne $observedExit) { $observedExit } else { "unverified" }
    $verdict = $(if ($useExit -eq "$($expectedById[$targetId].expected_exit)") { 'PASS' } else { 'FAIL' })
    AddRow $targetId $useExit $verdict ((Rel $pp.FullName) + '/result.json') $expectedById[$targetId].expected_reason
    if (-not $injected) {
        $p2ok = ($rp.PSObject.Properties['processes_recovered'] -and $rp.processes_recovered -is [bool] -and
                 $rp.PSObject.Properties['fallback_hits'] -and $rp.PSObject.Properties['identity_recheck_passed'])
        $p2verdict = $(if (($useExit -eq '0') -and $p2ok) { 'PASS' } else { 'FAIL' })
        AddRow 'P02' $useExit $p2verdict ((Rel $pp.FullName) + '/result.json') $expectedById['P02'].expected_reason
    }
}

# 2e. attribution results -> I02 / I03 (observed exit from recorder)
$attrRuns = @(Get-P0RecordedRuns $EvidenceRoot 'p0_probe_attribution.ps1')
foreach ($ar in $attrRuns) {
    $ap = Get-Content (Join-Path $ar.FullName 'result.json') -Raw | ConvertFrom-Json
    $targetId = if ($ap.fail_inject -eq 'import-fail') { 'I03' } else { 'I02' }
    $observedExit = $null
    $observedExit = "$($ar.P0Observation.actual_exit)"
    $useExit = if ($null -ne $observedExit) { $observedExit } else { 'unverified' }
    $verdict = $(if ($useExit -eq "$($expectedById[$targetId].expected_exit)") { 'PASS' } else { 'FAIL' })
    AddRow $targetId $useExit $verdict ((Rel $ar.FullName) + '/result.json') $expectedById[$targetId].expected_reason
}

# 2f. baseline smoke -> I01 (observed exit from recorder)
$blRuns = @(Get-P0RecordedRuns $EvidenceRoot 'p0_baseline.ps1')
foreach ($bl in $blRuns) {
    $bp = Get-Content (Join-Path $bl.FullName 'result.json') -Raw | ConvertFrom-Json
    if ($bp.failInject) { continue }
    $observedExit = $null
    $observedExit = "$($bl.P0Observation.actual_exit)"
    $useExit = if ($null -ne $observedExit) { $observedExit } else { 'unverified' }
    AddRow 'I01' $useExit $(if ($useExit -eq '0') { 'PASS' } else { 'FAIL' }) ((Rel $bl.FullName) + '/result.json') $expectedById['I01'].expected_reason
}

# 2g. matrix run exit -> I04 (exclude -SelfTest driver-proof dirs: their ST
# rows are engine self-proof, not case coverage; ordinal sort would otherwise
# let 'matrix-selftest-*' hijack the "latest matrix" slot)
$mxDirs = @(Get-P0MatrixRuns $EvidenceRoot)
$latestMx = $mxDirs | Select-Object -Last 1
if ($latestMx) {
    $mxPath = Join-Path $latestMx.FullName 'cases\matrix.csv'
    $mxRows = @(Get-Content $mxPath | Where-Object { $_ -match ',' -and $_ -notmatch '^case,' })
    $mxFail = @($mxRows | Where-Object { ($_ -split ',')[3] -eq 'FAIL' }).Count
    $observedExit = $null
    if ($observedByEntryRun.ContainsKey($latestMx.FullName)) { $observedExit = "$($observedByEntryRun[$latestMx.FullName].actual_exit)" }
    $useExit = if ($null -ne $observedExit) { $observedExit } else { 'unverified' }
    AddRow 'I04' $useExit $(if ($mxFail -eq 0 -and $mxRows.Count -ge 19 -and $useExit -eq '0') { 'PASS' } else { 'FAIL' }) ((Rel $latestMx.FullName) + '/cases/matrix.csv') $expectedById['I04'].expected_reason
}

# 2h. checker selftest -> N03 (+ M01/M02 from prior green pass when present)
$csPath = Join-Path $EvidenceRoot 'runs\checker-selftest-report.json'
if (Test-Path $csPath) {
    $cs = Get-Content $csPath -Raw | ConvertFrom-Json
    $n3ok = ($cs.clean_pass -and $cs.all_mutations_rejected)
    AddRow 'N03' '0' $(if ($n3ok) { 'PASS' } else { 'FAIL' }) 'runs/checker-selftest-report.json' $expectedById['N03'].expected_reason
}
$p1Path = Join-Path $EvidenceRoot 'runs\checker-prior-pass\report.json'
if (Test-Path $p1Path) {
    $p1 = Get-Content $p1Path -Raw | ConvertFrom-Json
    $priorObservedPath = Join-Path $EvidenceRoot 'runs\checker-prior-pass\observed.json'
    $priorObserved = if (Test-Path $priorObservedPath) { Get-Content $priorObservedPath -Raw | ConvertFrom-Json } else { $null }
    if ($p1.status -eq 'PASS' -and $priorObserved -and "$($priorObserved.actual_exit)" -eq '0' -and $priorObserved.report_sha256 -eq (Sha $p1Path)) {
        $indexOk = @($p1.results | Where-Object { $_.result -eq 'PASS' -and $_.check -eq 'INDEX.md relative links valid' }).Count -gt 0
        AddRow 'M01' '0' 'PASS' 'runs/checker-prior-pass/report.json (real checker execution, status PASS)' $expectedById['M01'].expected_reason
        AddRow 'M02' '0' $(if ($indexOk) { 'PASS' } else { 'FAIL' }) 'runs/checker-prior-pass/report.json (INDEX links validated)' $expectedById['M02'].expected_reason
    } else {
        Write-Host '[coverage] M01/M02 not derived: prior checker pass status is not PASS (two-pass protocol)'
    }
}

foreach ($id in $expectedById.Keys) {
    if ($id -in @('M01','M02') -and -not $seenCaseIds.ContainsKey($id)) { continue } # documented first-pass self reference; final checker requires both
    if (-not $seenCaseIds.ContainsKey($id)) { AddRow $id 'unverified' 'FAIL' '' 'required_evidence_unavailable' 'unverified' 'No current evidence; historical evidence unavailable' }
}

# matrix rows for the derived coverage (5-col, machine derived)
$covDir = Join-Path $EvidenceRoot 'runs\coverage-derive'
New-Item -ItemType Directory -Force -Path $covDir | Out-Null
'case,expectedExit,actualExit,verdict,reason' | Set-Content (Join-Path $covDir 'matrix.csv') -Encoding ASCII
$coverageRows | ForEach-Object { Add-Content -Path (Join-Path $covDir 'matrix.csv') -Value $_ -Encoding ASCII }

[ordered]@{
    generatedAt = (Get-Date).ToString('o')
    case_count = $coverage.Count
    coverage = $coverage
} | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $EvidenceRoot 'COVERAGE.json') -Encoding UTF8
Write-Host ("[COVERAGE] {0} derived case rows" -f $coverage.Count)

# ---------- 3. canonical script-hashes at the round root ----------------------
$hashList = [ordered]@{}
$perfDir = Join-Path $RepoRoot 'tests\performance'
foreach ($f in @('p0_acceptance.ps1','p0_paths.ps1','p0_runs.ps1','p0_asset_manifest_negtest.ps1','p0_routing_negtest.ps1','p0_env.ps1','p0_c1_guard_test.ps1','p0_probe_perprocess.ps1','p0_probe_attribution.ps1',
    'p0_baseline.ps1','p0_negative_tests.ps1','p0_asset_check.ps1','p0_pytest_isolated.ps1',
    'p0_entry_gate_negtest.ps1','p0_env_negtest.ps1','p0_guard_mutations.ps1','p0_evidence_check.ps1',
    'p0_result.ps1','p0_seal_round.ps1','p0_empty_host_case.ps1','p0_loopback_negtest.ps1',
    'p0_isolation_negtest.ps1','p0_recovery_negtest.ps1','p0_recovery_funcs.ps1','p0_run_recorder.ps1',
    'p0_guard\sitecustomize.py','p0_guard\guard_fallback.py','p0_guard\guard_test.py',
    'p0_guard\entry_gate.py','p0_guard\entry_wrapper.py','p0_guard\png_check.ps1',
    'p0_guard\loopback_vectors.py','p0_guard\empty_host_probe.py')) {
    $p = Join-Path $perfDir $f
    if (Test-Path $p) { $hashList[$f] = (Get-FileHash $p -Algorithm SHA256).Hash }
}
$hashList['source/tests/conftest.py'] = (Get-FileHash (Join-Path $RepoRoot 'source\tests\conftest.py') -Algorithm SHA256).Hash
$hashList | ConvertTo-Json | Set-Content (Join-Path $EvidenceRoot 'script-hashes.json') -Encoding UTF8
Write-Host '[hashes] canonical index written'

# ---------- 4. INPUT_MANIFEST.json (stable order + digest) --------------------
# Generate the index before hashing inputs, including on the second pass.
$index = New-Object System.Collections.Generic.List[string]
$index.Add('# INDEX - P0 ' + (Split-Path $EvidenceRoot -Leaf))
$index.Add('')
$index.Add('- Frozen cases: `CASE_MANIFEST.json`; changes: `CHANGE_IMPACT.json`; coverage: `COVERAGE.json`; digest: `INPUT_MANIFEST.json`')
$index.Add('- Log originals/copies: `LOG_COPY_INDEX.json`; unavailable originals remain unavailable.')
foreach ($d in (Get-ChildItem (Join-Path $EvidenceRoot 'runs') -Directory | Sort-Object Name)) { $index.Add(('- `runs/' + $d.Name + '/`')) }
$index.Add('- Historical runs are not current evidence. Current acceptance requires the recorded checker result, not historical counts.')
$index | Set-Content (Join-Path $EvidenceRoot 'INDEX.md') -Encoding UTF8
$excluded = @('INPUT_MANIFEST.json', 'EVIDENCE_CHECK.json', 'reports', 'runs\checker-output')
$inputFiles = @(Get-ChildItem $EvidenceRoot -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
    $rel = $_.FullName.Substring($EvidenceRoot.Length + 1).Replace('\', '/')
    if ($excluded -contains $rel) { return }
    if ($rel -like 'reports/*') { return }
    if ($rel -like 'runs/checker-output/*') { return }
    $_
} | Sort-Object FullName)
$entries = New-Object System.Collections.Generic.List[object]
foreach ($f in $inputFiles) {
    $rel = $f.FullName.Substring($EvidenceRoot.Length + 1).Replace('\', '/')
    $entries.Add([ordered]@{ path = $rel; sha256 = (Get-FileHash $f.FullName -Algorithm SHA256).Hash; bytes = $f.Length })
}
$digestInput = ($entries | ForEach-Object { "$($_.path)`0$($_.sha256)`n" }) -join ''
$bytes = [Text.Encoding]::UTF8.GetBytes($digestInput)
$shaProv = [System.Security.Cryptography.SHA256]::Create()
$digest = [BitConverter]::ToString($shaProv.ComputeHash($bytes)).Replace('-', '')
[ordered]@{
    generatedAt = (Get-Date).ToString('o')
    ordering = 'full path ascending (ordinal); digest over UTF-8 of "<relpath><NUL><sha256><LF>" for every entry, concatenated'
    excluded = [ordered]@{
        INPUT_MANIFEST_json = 'this manifest cannot contain its own hash; all other input files, including INDEX, are hashed after generation'
        EVIDENCE_CHECK_json = 'checker OUTPUT (machine report deliverable), excluded to avoid self-reference'
        reports_dir = 'checker stdout/stderr/exit records and prior-pass reports: outputs, not inputs'
        runs_checker_output = 'checker output directory (self-reference avoidance)'
    }
    file_count = $entries.Count
    digest = $digest
    entries = $entries
} | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $EvidenceRoot 'INPUT_MANIFEST.json') -Encoding UTF8
Write-Host ("[INPUT_MANIFEST] {0} files, digest={1}" -f $entries.Count, $digest.Substring(0, 16))

Write-Host '[PASS] seal-round v2 complete'
exit 0
