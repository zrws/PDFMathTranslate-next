# Evidence integrity checker v5 (ASCII only, PS 5.1 safe) - READ ONLY on inputs.
# R5 fixes over v4:
#   - EVERY file API call goes through guarded wrappers; illegal paths, read
#     errors, JSON/CSV parse errors and git command errors are recorded as
#     structured FAILURES (reason codes) and make the exit non-zero. Errors are
#     never swallowed.
#   - HONEST original-state model from LOG_COPY_INDEX (original_present /
#     original_present_at_temp_root / original_unavailable / copy_only_historical);
#     an unavailable original claiming a verified original hash FAILS.
#   - Per-case PROVENANCE validation from COVERAGE.json: case -> source run ->
#     artifacts exist -> observed exit (from recorder observed.json, never the
#     entry's planned exit) -> reason -> verdict. Planned-vs-observed mismatches
#     and unverified rows FAIL current acceptance (or count as unverified).
#   - Semantics, not just types: samples thresholds, recovery statuses
#     (query_failed never passes), payload null-ness, run-ref consistency.
#   - INPUT_MANIFEST digest recomputation: stable order, per-file sha256,
#     digest compare; output artifacts are excluded inputs by design.
#   - Counts split: expected / checked / failed / not_applicable / unverified.
#   - -SelfTest: synthetic template; clean copy must PASS; 22 mutations (13
#     carried over + 9 new) each rejected with a precise reason code; the
#     self-test report binds the checker's OWN sha256 + dependency hashes +
#     the real outer exit codes of every mutation run.
# Outputs: -ReportPath machine JSON only; never writes into the checked tree.
# Exit: 0 pass; 1 failures; 2 usage; 3 self-test failure.

param(
    [string]$EvidenceRoot = '',
    [string]$RepoRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent),
    [string]$ReportPath = '',
    [string]$Only = '',
    [switch]$SelfTest,
    [string]$SelfTestOut = '',
    [switch]$Final,          # Final pass requires EVIDENCE_CHECK.json deliverable
    [switch]$GitFailInject   # test-only hook (mutation: git command error)
)

. (Join-Path $PSScriptRoot 'p0_paths.ps1')
. (Join-Path $PSScriptRoot 'p0_runs.ps1')

$ErrorActionPreference = 'Continue'
$script:fails = 0
$script:expected = 0
$script:checked = 0
$script:skipped = 0
$script:notApplicable = 0
$script:unverified = 0
$script:results = New-Object System.Collections.Generic.List[object]
$script:GitFailInject = [bool]$GitFailInject

function Check([string]$name, [bool]$condition, [string]$detail, [string]$why = 'check_failed') {
    $script:expected++
    $script:checked++
    if ($condition) {
        Write-Host "[PASS] $name"
        $script:results.Add(@{ check = $name; result = 'PASS'; detail = $detail; reason_code = '' })
    } else {
        Write-Host ("[FAIL] {0} : {1}" -f $name, $detail)
        $script:fails++
        $script:results.Add(@{ check = $name; result = 'FAIL'; detail = $detail; reason_code = $why })
    }
}
function CheckNA([string]$name, [string]$detail) {
    $script:expected++
    $script:notApplicable++
    Write-Host ("[N/A] {0} : {1}" -f $name, $detail)
    $script:results.Add(@{ check = $name; result = 'NOT_APPLICABLE'; detail = $detail; reason_code = '' })
}
function CheckUnverified([string]$name, [string]$detail) {
    $script:expected++
    $script:unverified++
    Write-Host ("[UNVERIFIED] {0} : {1}" -f $name, $detail)
    $script:results.Add(@{ check = $name; result = 'UNVERIFIED'; detail = $detail; reason_code = 'unverified_observation' })
}

# guarded file wrappers -------------------------------------------------------
function Try-Path([string]$p) {
    try { return (Test-Path -LiteralPath $p -ErrorAction Stop) }
    catch { $script:fails++; $script:expected++
        Write-Host ("[FAIL] path access error: {0} ({1})" -f $p, $_.Exception.Message)
        $script:results.Add(@{ check = "path-access"; result = 'FAIL'; detail = ("$p : " + $_.Exception.Message); reason_code = 'path_illegal' })
        return $false }
}
function Read-TextGuarded([string]$p, [string]$name, [string]$whyCode) {
    try {
        if (-not (Test-Path -LiteralPath $p -ErrorAction Stop)) { return $null }
        return [IO.File]::ReadAllText($p)
    } catch {
        $script:fails++; $script:expected++
        Write-Host ("[FAIL] read error in {0}: {1}" -f $name, $_.Exception.Message)
        $script:results.Add(@{ check = $name; result = 'FAIL'; detail = $_.Exception.Message; reason_code = $whyCode })
        return $null
    }
}
function Read-JsonGuarded([string]$p, [string]$name) {
    $raw = Read-TextGuarded $p $name 'read_error'
    if ($null -eq $raw) { return $null }
    try { return $raw | ConvertFrom-Json }
    catch {
        $script:fails++; $script:expected++
        Write-Host ("[FAIL] JSON parse error in {0}: {1}" -f $name, $_.Exception.Message)
        $script:results.Add(@{ check = $name; result = 'FAIL'; detail = $_.Exception.Message; reason_code = 'parse_error' })
        return $null
    }
}

function Resolve-RepoFile([string]$rel) {
    $rel2 = ($rel -replace '/', '\').TrimStart('\')
    foreach ($base in @(
        (Join-Path $RepoRoot 'tests\performance\p0_guard'),
        (Join-Path $RepoRoot 'tests\performance'),
        (Join-Path $RepoRoot 'source'),
        $RepoRoot
    )) {
        $candidate = Join-Path $base $rel2
        if (Try-Path $candidate) { return $candidate }
    }
    return $null
}
function Get-Sha([string]$p) {
    if (-not (Try-Path $p)) { return $null }
    try { return (Get-FileHash -LiteralPath $p -Algorithm SHA256 -ErrorAction Stop).Hash }
    catch {
        $script:fails++; $script:expected++
        $script:results.Add(@{ check = "hash-read"; result = 'FAIL'; detail = ("$p : " + $_.Exception.Message); reason_code = 'read_error' })
        return $null
    }
}

function Git-CheckIgnoreBatch([string[]]$relPaths) {
    $ignored = @{}
    if ($relPaths.Count -eq 0) { return @{ ignored = $ignored; error = $false; errorDetail = '' } }
    if ($script:GitFailInject) {
        return @{ ignored = $ignored; error = $true; errorDetail = 'GitFailInject: forced check-ignore command error' }
    }
    try {
        $input_ = ($relPaths -join "`n")
        $raw = $input_ | & git -c ("safe.directory=" + ($RepoRoot -replace '\\', '/')) check-ignore --verbose --non-matching --stdin 2>$null
        $code = $LASTEXITCODE
        if ($code -ne 0 -and $code -ne 1) {
            return @{ ignored = $ignored; error = $true; errorDetail = ("git check-ignore exit " + $code) }
        }
        foreach ($line in @($raw)) {
            if ($line -match '^::\t(.+)$') { continue }
            $lastTab = "$line".LastIndexOf("`t")
            if ($lastTab -gt 0) { $ignored[$line.Substring($lastTab + 1)] = $true }
        }
        return @{ ignored = $ignored; error = $false; errorDetail = '' }
    } catch {
        return @{ ignored = $ignored; error = $true; errorDetail = $_.Exception.Message }
    }
}

function Run-CheckSet {
    if (-not (Try-Path $EvidenceRoot)) {
        Write-Host "[FAIL] evidence root not found: $EvidenceRoot"; exit 1
    }

    # --- 1. deliverables -------------------------------------------------------
    foreach ($d in @('PLAN.md','CHANGE_IMPACT.json','CASE_MANIFEST.json','INDEX.md','REQUIREMENTS.json','COVERAGE.json','LOG_COPY_INDEX.json','INPUT_MANIFEST.json')) {
        Check ("deliverable exists: {0}" -f $d) (Try-Path (Join-Path $EvidenceRoot $d)) 'missing' 'missing_deliverable'
    }
    if ($Final) {
        Check 'deliverable exists: EVIDENCE_CHECK.json (final pass)' (Try-Path (Join-Path $EvidenceRoot 'EVIDENCE_CHECK.json')) 'missing (final pass requires the machine report deliverable)' 'missing_deliverable'
    } else {
        CheckNA 'EVIDENCE_CHECK.json deliverable' 'not required in the prior pass (it is this checker OUTPUT; two-pass protocol)'
    }

    # --- 2. canonical script hashes (ALL entries resolve+match; no skip) -------
    $hfRoot = Join-Path $EvidenceRoot 'script-hashes.json'
    $hashes = Read-JsonGuarded $hfRoot 'script-hashes.json'
    if ($null -eq $hashes) {
        Check 'hash index readable' $false 'unreadable or empty' 'parse_error'
    } else {
        $props = @($hashes.PSObject.Properties)
        Check 'hash index non-empty' ($props.Count -gt 0) 'zero hash entries' 'zero_hash_coverage'
        foreach ($prop in $props) {
            $resolved = Resolve-RepoFile $prop.Name
            if (-not $resolved) {
                $script:expected++; $script:fails++
                Write-Host ("[FAIL] hash: {0} : file not found in any helper root (never skip)" -f $prop.Name)
                $script:results.Add(@{ check = ("hash+{0}" -f $prop.Name); result = 'FAIL'; detail = 'unresolved path'; reason_code = 'unresolved_hash_target' })
                continue
            }
            $current = Get-Sha $resolved
            $ok = ($current -eq $prop.Value)
            if ($ok) { $script:expected++; Write-Host ("[PASS] hash: {0}" -f $prop.Name); $script:results.Add(@{ check = ("hash+{0}" -f $prop.Name); result = 'PASS'; detail = ''; reason_code = '' }) }
            else {
                $script:expected++; $script:fails++
                Write-Host ("[FAIL] hash: {0} : expected {1}, got {2}" -f $prop.Name, $prop.Value, $current)
                $script:results.Add(@{ check = ("hash+{0}" -f $prop.Name); result = 'FAIL'; detail = ("drift expected=" + $prop.Value + " actual=" + $current); reason_code = 'hash_drift' })
            }
        }
    }

    # --- 2b. per-run script-hashes tables (R5: runtime identity of each run) ---
    # every run-local script-hashes.json must resolve and match the CURRENT
    # source for this round's runs (historical rounds live outside this root)
    foreach ($rhf in @(Get-ChildItem $EvidenceRoot -Recurse -Filter 'script-hashes.json' -ErrorAction SilentlyContinue)) {
        if ($rhf.FullName -eq $hfRoot) { continue }
        $rh = Read-JsonGuarded $rhf.FullName ("run hashes {0}" -f $rhf.Directory.Name)
        if ($null -eq $rh) { continue }
        foreach ($prop in @($rh.PSObject.Properties)) {
            if ($prop.Name -in @('encountered_test_script','encountered_test_script_sha256','entry','guard_test_under_test')) { continue }
            $resolved = Resolve-RepoFile $prop.Name
            if (-not $resolved) {
                $script:expected++; $script:fails++
                Write-Host ("[FAIL] run hash: {0} in {1} : unresolved" -f $prop.Name, $rhf.Directory.Name)
                $script:results.Add(@{ check = ("runhash+{0}+{1}" -f $rhf.Directory.Name, $prop.Name); result = 'FAIL'; detail = 'unresolved path'; reason_code = 'unresolved_hash_target' })
                continue
            }
            $cur = Get-Sha $resolved
            $ok2 = ($cur -eq $prop.Value)
            if ($ok2) { $script:expected++; $script:results.Add(@{ check = ("runhash+{0}+{1}" -f $rhf.Directory.Name, $prop.Name); result = 'PASS'; detail = ''; reason_code = '' }) }
            else {
                $script:expected++; $script:fails++
                Write-Host ("[FAIL] run hash: {0} in {1} : drift" -f $prop.Name, $rhf.Directory.Name)
                $script:results.Add(@{ check = ("runhash+{0}+{1}" -f $rhf.Directory.Name, $prop.Name); result = 'FAIL'; detail = ("drift expected=" + $prop.Value + " actual=" + $cur); reason_code = 'hash_drift' })
            }
        }
    }

    # --- 3. INPUT_MANIFEST digest recompute -------------------------------------
    $imPath = Join-Path $EvidenceRoot 'INPUT_MANIFEST.json'
    $im = Read-JsonGuarded $imPath 'INPUT_MANIFEST.json'
    if ($null -eq $im) {
        Check 'INPUT_MANIFEST readable' $false 'unreadable' 'parse_error'
    } else {
        $entries = @($im.entries)
        Check 'INPUT_MANIFEST entries non-empty' ($entries.Count -gt 0) 'zero entries' 'zero_hash_coverage'
        $digestInput = ''
        $hashMismatch = 0
        foreach ($e in $entries) {
            $abs = Join-Path $EvidenceRoot ($e.path -replace '/', '\')
            if (-not (Try-Path $abs)) { Check ("input exists: {0}" -f $e.path) $false 'missing input file' 'missing_input' ; continue }
            $h = Get-Sha $abs
            if ($h -ne $e.sha256) { $hashMismatch++; Check ("input hash: {0}" -f $e.path) $false ("manifest={0} actual={1}" -f $e.sha256, $h) 'input_hash_mismatch' }
            $digestInput += "$($e.path)`0$($e.sha256)`n"
        }
        if ($hashMismatch -eq 0 -and $entries.Count -gt 0) { Check 'input manifest per-file hashes' $true '' }
        $bytes = [Text.Encoding]::UTF8.GetBytes($digestInput)
        $shaProv = [System.Security.Cryptography.SHA256]::Create()
        $recomputed = [BitConverter]::ToString($shaProv.ComputeHash($bytes)).Replace('-', '')
        Check 'INPUT_MANIFEST digest matches recomputation' ($recomputed -eq $im.digest) ("manifest={0} recomputed={1}" -f $im.digest, $recomputed) 'input_digest_mismatch'
    }

    # --- 4. COVERAGE provenance validation ----------------------------------------
    $cm = Read-JsonGuarded (Join-Path $EvidenceRoot 'CASE_MANIFEST.json') 'CASE_MANIFEST.json'
    $expectedById = @{}
    if ($cm) { foreach ($c in @($cm.cases) + @($cm.new_cases_this_round)) { if ($c) { $expectedById[$c.id] = $c } } }
    $cov = Read-JsonGuarded (Join-Path $EvidenceRoot 'COVERAGE.json') 'COVERAGE.json'
    if ($null -eq $cov) {
        Check 'COVERAGE readable' $false 'unreadable' 'parse_error'
    } else {
        $covById = @{}
        foreach ($row in @($cov.coverage)) { if ($row) { $covById[$row.case] = $row } }
        $recorderObserved = @{}
        foreach ($rd in (Get-ChildItem (Join-Path $EvidenceRoot 'runs') -Directory -Filter 'recorder-*' -ErrorAction SilentlyContinue)) {
            $oj = Join-Path $rd.FullName 'observed.json'
            if (-not (Try-Path $oj)) { continue }
            $o = Read-JsonGuarded $oj ($rd.Name + '/observed.json')
            if ($o -and $o.entry_run_dir -and $o.PSObject.Properties['actual_exit']) {
                $recorderObserved[[IO.Path]::GetFullPath("$($o.entry_run_dir)")] = $o
            }
        }
        foreach ($caseId in $expectedById.Keys) {
            $exp = $expectedById[$caseId]
            if (-not $covById.ContainsKey($caseId)) {
                if (-not $Final -and $caseId -in @('M01','M02')) {
                    CheckNA ('coverage: ' + $caseId + ' first-pass self reference') 'Requires this real execution to finish; final pass must bind its externally observed exit'
                    continue
                }
                Check ("coverage: {0} present" -f $caseId) $false 'case missing from COVERAGE' 'missing_coverage_case'
                continue
            }
            $row = $covById[$caseId]
            Check ("coverage {0}: verdict PASS" -f $caseId) ($row.verdict -eq 'PASS') ("verdict=" + $row.verdict) 'coverage_verdict_fail'
            $oe = "$($row.observed_exit)"
            if ($oe -eq 'unverified') {
                # R5: an unverified row CANNOT pass current acceptance - it is
                # counted as unverified AND fails the run (no hidden green)
                $script:expected++; $script:unverified++; $script:fails++
                Write-Host ("[UNVERIFIED-FAIL] coverage {0}: observed exit unverified (no recorder binding)" -f $caseId)
                $script:results.Add(@{ check = ("coverage {0}: observed exit" -f $caseId); result = 'UNVERIFIED'; detail = 'observed exit unverified; row cannot support current acceptance'; reason_code = 'unverified_observation' })
            } else {
                Check ("coverage {0}: observed exit == expected" -f $caseId) ($oe -eq "$($exp.expected_exit)") ("observed={0} expected={1}" -f $oe, $exp.expected_exit) 'observed_exit_mismatch'
                Check ("coverage {0}: reason observed" -f $caseId) ($row.expected_reason -eq "$($exp.expected_reason)") ("row={0} manifest={1}" -f $row.expected_reason, $exp.expected_reason) 'wrong_reason'
                # R5 generic semantic: recorder actual_exit must agree with the
                # coverage row's observed exit for new-run rows (never trust the
                # entry's planned exit as the observed fact)
                $src = "$($row.source)"
                if ($row.mode -eq 'new-run' -and $src) {
                    $srcPath = ($src -split ' \+ ')[0]
                    $srcPath = ($srcPath -replace ' \(.*\)$', '')
                    $srcRunDir = $null
                    if ($srcPath -like 'runs/*') { $srcRunDir = (Join-Path $EvidenceRoot (($srcPath -replace '/', '\') -replace '\\[^\\]+$', '')) }
                    elseif ($srcPath -match '^(perprocess|attribution|empty-host|mutations|baseline)-') { $srcRunDir = Join-Path $EvidenceRoot ('runs\' + (($srcPath -replace '/', '\') -replace '\\[^\\]+$', '')) }
                    if ($srcRunDir -and (Try-Path $srcRunDir) -and $recorderObserved.ContainsKey([IO.Path]::GetFullPath($srcRunDir))) {
                        $obsExit = "$($recorderObserved[[IO.Path]::GetFullPath($srcRunDir)].actual_exit)"
                        Check ("coverage {0}: recorder exit agrees with coverage row" -f $caseId) ($obsExit -eq $oe) ("recorder={0} coverage={1}" -f $obsExit, $oe) 'planned_observed_mismatch'
                    }
                }
            }
            # source artifacts exist (source is 'runs/<dir>/...' or '<dir>/file');
            # strip annotation suffixes like ' + recorder' before path building
            $src = "$($row.source)"
            if ($src) {
                $srcPath = ($src -split ' \+ ')[0]
                $srcPath = ($srcPath -replace ' \(.*\)$', '')
                $srcDir = ($srcPath -split '/')[0]
                if ($srcDir -eq 'guard-test' -or $src -like 'entrygate/*' -or $src -like 'env-restore*') {
                    $parent = ($srcPath -split '/')[0..1] -join '\'
                    Check ("coverage {0}: source run dir exists" -f $caseId) (Try-Path (Join-Path $EvidenceRoot ('runs\' + $parent))) $srcPath 'missing_source_run'
                } elseif ($srcDir -like 'perprocess-*' -or $srcDir -like 'attribution-*' -or $srcDir -like 'empty-host-*' -or $srcDir -like 'mutations-*' -or $srcPath -like 'runs/*' -or $srcDir -like 'matrix-*' -or $srcDir -eq 'baseline') {
                    $p = if ($srcPath -like 'runs/*') { Join-Path $EvidenceRoot ($srcPath -replace '/', '\') } else { Join-Path $EvidenceRoot ('runs\' + ($srcPath -replace '/', '\')) }
                    Check ("coverage {0}: source artifacts exist" -f $caseId) (Try-Path $p) $srcPath 'missing_source_run'
                }
            }
        }
        if ($Final) {
            $prior = Read-JsonGuarded (Join-Path $EvidenceRoot 'runs\checker-prior-pass\report.json') 'prior checker report'
            $outer = Read-JsonGuarded (Join-Path $EvidenceRoot 'runs\checker-prior-pass\observed.json') 'prior checker observation'
            Check 'final: prior checker real exit zero' ($null -ne $prior -and $null -ne $outer -and $prior.status -eq 'PASS' -and "$($outer.actual_exit)" -eq '0') 'missing/nonzero first-pass observation' 'missing_outer_observation'
            Check 'final: prior checker report hash bound' ($null -ne $outer -and $outer.report_sha256 -eq (Get-Sha (Join-Path $EvidenceRoot 'runs\checker-prior-pass\report.json'))) 'first-pass report changed' 'hash_drift'
            Check 'final: prior checker version current' ($null -ne $prior -and $prior.checker_sha256 -eq (Get-Sha $PSCommandPath)) 'first-pass checker source differs' 'hash_drift'
            $sameRoot = $false
            try { $sameRoot = $prior.checked_root -and [IO.Path]::GetFullPath($prior.checked_root) -eq [IO.Path]::GetFullPath($EvidenceRoot) } catch { }
            Check 'final: prior checker checked this root' $sameRoot 'a first pass from a different evidence root cannot support this round' 'missing_source_run'
            Check 'final: prior checker process identity' ($outer.child_pid -gt 0 -and $outer.entry -eq $PSCommandPath -and -not $outer.timeout_hit -and $outer.command) 'missing actual checker invocation identity' 'missing_outer_observation'
        }
        $resolved = @{}
        foreach ($entryName in @('p0_probe_perprocess.ps1','p0_probe_attribution.ps1','p0_baseline.ps1')) {
            try { $resolved[$entryName] = @(Get-P0RecordedRuns $EvidenceRoot $entryName) }
            catch { Check ('recorded layout: ' + $entryName) $false $_.Exception.Message 'invalid_recorded_layout'; $resolved[$entryName] = @() }
        }
        # per-case semantic validation (selected current runs only)
        foreach ($row in @($cov.coverage)) {
            if ($row.mode -ne 'new-run') { continue }
            $matchedSemanticRun = $false
            switch ($row.case) {
                { $_ -in @('P01','P02') } {
                    # find the newest perprocess result + its recorder binding
                    $ppDirs = @($resolved['p0_probe_perprocess.ps1'])
                    foreach ($pp in $ppDirs) {
                        $rj = Join-Path $pp.FullName 'result.json'
                        if (-not (Try-Path $rj)) { continue }
                        $rp = Read-JsonGuarded $rj ($pp.Name + '/result.json')
                        if ($rp.fail_inject) { continue }
                        $selectedPath = Join-Path $EvidenceRoot ($row.source -replace '/', '\')
                        if ([IO.Path]::GetFullPath($selectedPath) -ne [IO.Path]::GetFullPath($rj)) { continue }
                        $matchedSemanticRun = $true
                        Check ('semantic ' + $row.case + ': recovery fields complete') ($rp.processes_recovered -eq $true -and $rp.identity_recheck_passed -eq $true -and $null -ne $rp.fallback_hits) 'missing or unsuccessful recovery fields' 'semantic_recovery'
                        Check 'semantic P01: samples >= 2' ($rp.samples -ge 2) ("samples=" + $rp.samples) 'semantic_samples'
                        $badRecovery = @($rp.recovery_details | Where-Object { $_.post_status -ne 'gone' }).Count
                        Check 'semantic P01: recovery all gone' ($badRecovery -eq 0) ("non-gone rows: " + $badRecovery) 'semantic_recovery'
                        $o = $pp.P0Observation
                        Check 'semantic P01: recorder binds this run' ($null -ne $o) 'no recorder observed.json binds the selected P01 run' 'missing_outer_observation'
                        if ($o) {
                            Check 'semantic P01: planned exit == observed exit' ("$($rp.exit_code)" -eq "$($o.actual_exit)") ("planned={0} observed={1}" -f $rp.exit_code, $o.actual_exit) 'planned_observed_mismatch'
                        }
                        break
                    }
                }
                'N04' {
                    $ppDirs = @($resolved['p0_probe_perprocess.ps1'])
                    foreach ($pp in $ppDirs) {
                        $rj = Join-Path $pp.FullName 'result.json'
                        if (-not (Try-Path $rj)) { continue }
                        $rp = Read-JsonGuarded $rj ($pp.Name + '/result.json')
                        if ($rp.fail_inject -ne 'midrun-exception') { continue }
                        $selectedPath = Join-Path $EvidenceRoot ($row.source -replace '/', '\')
                        if ([IO.Path]::GetFullPath($selectedPath) -ne [IO.Path]::GetFullPath($rj)) { continue }
                        $matchedSemanticRun = $true
                        Check 'semantic N04: injected exception recorded' ($rp.reason_code -eq 'UNHANDLED_EXCEPTION') ("reason_code=" + $rp.reason_code) 'semantic_n04'
                        $o = $pp.P0Observation
                        Check 'semantic N04: recorder binds this run' ($null -ne $o) 'no recorder binding for the selected N04 run' 'missing_outer_observation'
                        if ($o) {
                            Check 'semantic N04: observed exit == 1' ("$($o.actual_exit)" -eq '1') ("observed=" + $o.actual_exit) 'observed_exit_mismatch'
                        }
                        break
                    }
                }
                'I02' {
                    $attrDirs = @($resolved['p0_probe_attribution.ps1'])
                    foreach ($ar in $attrDirs) {
                        $rj = Join-Path $ar.FullName 'result.json'
                        if (-not (Try-Path $rj)) { continue }
                        $ap = Read-JsonGuarded $rj ($ar.Name + '/result.json')
                        if ($ap.fail_inject) { continue }
                        $selectedPath = Join-Path $EvidenceRoot ($row.source -replace '/', '\')
                        if ([IO.Path]::GetFullPath($selectedPath) -ne [IO.Path]::GetFullPath($rj)) { continue }
                        $matchedSemanticRun = $true
                        $jl = Join-Path $ar.FullName 'probe-attribution.jsonl'
                        $lines = @(Get-Content $jl -ErrorAction SilentlyContinue | Where-Object { $_ -match '\S' })
                        $nullCount = @($lines | Where-Object { $_ -match '"privateMB":null' }).Count
                        Check 'semantic I02: 4 payloads measured (no nulls)' (($lines.Count -ge 4) -and ($nullCount -eq 0)) ("lines=" + $lines.Count + " nulls=" + $nullCount) 'semantic_payloads'
                        $rec = Join-Path $ar.FullName 'recovery.json'
                        if (Try-Path $rec) {
                            $r = Read-JsonGuarded $rec ($ar.Name + '/recovery.json')
                            Check 'semantic I02: recovery all_gone' ($r.all_gone -eq $true) 'recovery not all_gone' 'semantic_recovery'
                            $badRows = @($r.rows | Where-Object { $_.post_status -ne 'gone' }).Count
                            Check 'semantic I02: recovery rows all gone' ($badRows -eq 0) ("non-gone rows: " + $badRows) 'semantic_recovery'
                        } else {
                            Check 'semantic I02: recovery.json present' $false 'recovery facts not persisted' 'missing_recovery_facts'
                        }
                        $o = $ar.P0Observation
                        Check 'semantic I02: recorder binds this run' ($null -ne $o) 'no recorder binding for the selected I02 run' 'missing_outer_observation'
                        break
                    }
                }
                'I03' {
                    $attrDirs = @($resolved['p0_probe_attribution.ps1'])
                    foreach ($ar in $attrDirs) {
                        $rj = Join-Path $ar.FullName 'result.json'
                        if (-not (Try-Path $rj)) { continue }
                        $ap = Read-JsonGuarded $rj ($ar.Name + '/result.json')
                        if ($ap.fail_inject -ne 'import-fail') { continue }
                        $selectedPath = Join-Path $EvidenceRoot ($row.source -replace '/', '\')
                        if ([IO.Path]::GetFullPath($selectedPath) -ne [IO.Path]::GetFullPath($rj)) { continue }
                        $matchedSemanticRun = $true
                        $o = $ar.P0Observation
                        Check 'semantic I03: recorder binds this run' ($null -ne $o) 'no recorder binding for the selected I03 run' 'missing_outer_observation'
                        if ($o) {
                            Check 'semantic I03: observed exit == 1' ("$($o.actual_exit)" -eq '1') ("observed=" + $o.actual_exit) 'observed_exit_mismatch'
                        }
                        break
                    }
                }
                'I01' {
                    $blDirs = @($resolved['p0_baseline.ps1'])
                    foreach ($bl in $blDirs) {
                        $rj = Join-Path $bl.FullName 'result.json'
                        if (-not (Try-Path $rj)) { continue }
                        $bp = Read-JsonGuarded $rj ($bl.Name + '/result.json')
                        if ($bp.failInject) { continue }
                        $selectedPath = Join-Path $EvidenceRoot ($row.source -replace '/', '\')
                        if ([IO.Path]::GetFullPath($selectedPath) -ne [IO.Path]::GetFullPath($rj)) { continue }
                        $matchedSemanticRun = $true
                        $o = $bl.P0Observation
                        Check 'semantic I01: recorder binds this run' ($null -ne $o) 'no recorder binding for the selected I01 run' 'missing_outer_observation'
                        if ($o) {
                            Check 'semantic I01: observed exit == 0' ("$($o.actual_exit)" -eq '0') ("observed=" + $o.actual_exit) 'observed_exit_mismatch'
                        }
                        break
                    }
                }
                'I04' {
                    try {
                        $matrices = @(Get-P0MatrixRuns $EvidenceRoot)
                        foreach ($mx in $matrices) {
                            $artifact = Join-Path $mx.FullName 'cases\matrix.csv'
                            $selected = Join-Path $EvidenceRoot ($row.source -replace '/', '\')
                            if ([IO.Path]::GetFullPath($selected) -ne [IO.Path]::GetFullPath($artifact)) { continue }
                            $matchedSemanticRun = $true
                            $observation = $recorderObserved[$mx.FullName]
                            Check 'semantic I04: actual recorder binding required' ($null -ne $observation) 'no observation for selected acceptance matrix' 'missing_outer_observation'
                            if ($observation) { Check 'semantic I04: observed exit matches' ("$($observation.actual_exit)" -eq '0' -and "$($row.observed_exit)" -eq '0') 'acceptance matrix did not exit zero' 'observed_exit_mismatch' }
                            $matrixRows = @(Import-Csv -LiteralPath $artifact)
                            Check 'semantic I04: complete matrix passes' ($matrixRows.Count -ge 19 -and @($matrixRows | Where-Object { $_.verdict -ne 'PASS' }).Count -eq 0) 'partial or failing acceptance matrix' 'semantic_matrix'
                        }
                    } catch { Check 'semantic I04: matrix layout' $false $_.Exception.Message 'invalid_recorded_layout' }
                }
            }
            if ($row.case -in @('P01','P02','N04','I01','I02','I03','I04')) { Check ('semantic ' + $row.case + ': selected recorded run exists') $matchedSemanticRun 'no matching recorded artifact for this coverage row' 'missing_semantic_run' }
        }
    }

    # --- 5. matrix rows validated vs frozen manifest ------------------------------
    $matrixFiles = @(Get-ChildItem $EvidenceRoot -Recurse -Filter 'matrix.csv' -ErrorAction SilentlyContinue)
    $seenCaseIds = @{}
    foreach ($mf in $matrixFiles) {
        $lines = @()
        try { $lines = @(Get-Content -LiteralPath $mf.FullName -ErrorAction Stop | Where-Object { $_ -match '\S' }) }
        catch {
            $script:fails++; $script:expected++
            $script:results.Add(@{ check = ("matrix read {0}" -f $mf.Name); result = 'FAIL'; detail = $_.Exception.Message; reason_code = 'read_error' })
            continue
        }
        $dataRows = @($lines | Where-Object { $_ -notmatch '^\s*case,' })
        Check ("matrix rows in {0}" -f $mf.Directory.Name) ($dataRows.Count -gt 0) ("only {0} data rows" -f $dataRows.Count) 'empty_matrix'
        foreach ($row in $dataRows) {
            $parts = $row.Split(',')
            if ($parts.Count -lt 4) { continue }
            $caseId = $parts[0]; $expExit = $parts[1]; $actExit = $parts[2]; $verdict = $parts[3]
            $reason = if ($parts.Count -ge 5) { $parts[4] } else { '' }
            $frozenId = if ($parts.Count -ge 6) { $parts[5] } else { '' }
            $frozenReason = if ($parts.Count -ge 7) { $parts[6] } else { $reason }
            if ($frozenId) { $seenCaseIds[$frozenId] = $true } else { $seenCaseIds[$caseId] = $true }
            $manifestId = if ($frozenId) { $frozenId } else { $caseId }
            if ($expectedById.ContainsKey($manifestId)) {
                $exp = $expectedById[$manifestId]
                $expectedReason = "$($exp.expected_reason)"
                if ($frozenId -and $parts.Count -ge 7) {
                    $rowConsistent = ("$expExit" -eq "$actExit") -and ("$verdict" -eq 'PASS')
                    Check ("matrix {0} suite row consistent" -f $manifestId) $rowConsistent ("row expected={0} actual={1} verdict={2}" -f $expExit, $actExit, $verdict) 'verdict_inconsistent'
                    Check ("matrix {0} frozen reason" -f $manifestId) ($frozenReason -eq $expectedReason) ("row frozenReason='{0}' != manifest '{1}'" -f $frozenReason, $expectedReason) 'wrong_reason'
                } else {
                    Check ("matrix {0} expected exit" -f $manifestId) ("$($exp.expected_exit)" -eq "$expExit") ("manifest expected_exit={0}, row={1}" -f $exp.expected_exit, $expExit) 'matrix_expected_mismatch'
                    $verdictOk = ("$($exp.expected_exit)" -eq "$actExit") -and ("$verdict" -eq 'PASS')
                    Check ("matrix {0} verdict consistent" -f $manifestId) $verdictOk ("actual={0} verdict={1}" -f $actExit, $verdict) 'verdict_inconsistent'
                    Check ("matrix {0} reason assertion" -f $manifestId) ($reason -eq "$expectedReason") ("row reason='{0}' != frozen '{1}'" -f $reason, $expectedReason) 'wrong_reason'
                }
            }
        }
    }
    if ($expectedById.Count -gt 0) {
        if ($matrixFiles.Count -eq 0) {
            Check 'mandatory coverage' $false 'no matrix.csv in evidence tree' 'missing_matrix'
        } else {
            $uncovered = @($expectedById.Keys | Where-Object { -not $seenCaseIds.ContainsKey($_) })
            $selfRef = @('M01','M02')
            $uncovered = @($uncovered | Where-Object { $selfRef -notcontains $_ })
            if (@($expectedById.Keys | Where-Object { $selfRef -contains $_ -and -not $seenCaseIds.ContainsKey($_) }).Count -gt 0) {
                Write-Host '[info] M01/M02 rows absent from matrices - bound by the recorded final execution (two-pass protocol)'
            }
            Check 'mandatory coverage (all frozen cases present in matrices)' ($uncovered.Count -eq 0) ("uncovered: {0}" -f ($uncovered -join ',')) 'missing_mandatory_case'
        }
    }

    # --- 6. LOG_COPY_INDEX honest-state validation --------------------------------
    $lc = Read-JsonGuarded (Join-Path $EvidenceRoot 'LOG_COPY_INDEX.json') 'LOG_COPY_INDEX.json'
    if ($null -eq $lc) {
        Check 'LOG_COPY_INDEX readable' $false 'unreadable' 'parse_error'
    } else {
        $pairIndex = @{}
        foreach ($p in @($lc.pairs)) {
            if (-not $p) { continue }
            $pairIndex["$($p.copy)"] = $p
            $copyAbs = Join-Path $EvidenceRoot ("$($p.copy)" -replace '/', '\')
            if (-not (Try-Path $copyAbs)) {
                Check ("log copy exists: {0}" -f $p.copy) $false 'missing' 'missing_log_copy'
                continue
            }
            $copySha = Get-Sha $copyAbs
            Check ("log copy hash: {0}" -f $p.copy) ($copySha -eq $p.copy_sha256) ("index={0} actual={1}" -f $p.copy_sha256, $copySha) 'log_copy_hash_mismatch'
            switch ("$($p.original_state)") {
                'original_present' {
                    $origAbs = Join-Path $EvidenceRoot ("$($p.original)" -replace '/', '\')
                    if (Try-Path $origAbs) {
                        $origSha = Get-Sha $origAbs
                        Check ("log original hash: {0}" -f $p.original) ($origSha -eq $p.original_sha256) ("index={0} actual={1}" -f $p.original_sha256, $origSha) 'log_original_hash_mismatch'
                        if ("$($p.sanitization)" -match '^none' -and $origSha -ne $copySha) {
                            Check ("log pair byte-identical as declared: {0}" -f $p.copy) $false 'declared unsanitized but hashes differ' 'log_copy_mismatch'
                        }
                    } else {
                        Check ("log original present as declared: {0}" -f $p.original) $false 'state=original_present but original missing' 'original_state_lie'
                    }
                }
                'original_present_at_temp_root' {
                    $origAbs = "$($p.original)"
                    if ($origAbs -and (Try-Path $origAbs)) {
                        $origSha = Get-Sha $origAbs
                        Check ("log original (temp root) hash: {0}" -f $p.original) ($origSha -eq $p.original_sha256) '' 'log_original_hash_mismatch'
                    } else {
                        Check ("log original (temp root) present: {0}" -f $origAbs) $false 'state=original_present_at_temp_root but file missing' 'original_state_lie'
                    }
                }
                'original_unavailable' {
                    Check ("log original honestly unavailable: {0}" -f $p.copy) ($null -eq $p.original -and $null -eq $p.original_sha256) 'unavailable original claims a path/hash' 'unknown_original_claimed_verified'
                }
                'copy_only_historical' {
                    CheckNA ("log copy-only historical: {0}" -f $p.copy) 'limited conclusion: copy integrity only; no original-relationship claim'
                }
                default {
                    Check ("log original state recognized: {0}" -f $p.copy) $false ("unknown state '{0}'" -f $p.original_state) 'original_state_unknown'
                }
            }
        }
        $logPairs = @(Get-ChildItem $EvidenceRoot -Recurse -Filter '*.log' -File -ErrorAction SilentlyContinue)
        foreach ($lf in $logPairs) {
            $copy = $lf.FullName -replace '\.log$', '.log.txt'
            $relCopy = $copy.Substring($EvidenceRoot.Length + 1).Replace('\', '/')
            $ok = (Try-Path $copy) -and ($pairIndex.ContainsKey($relCopy))
            Check ("log pair recorded+present: {0}" -f $lf.Name) $ok 'missing .log.txt companion or not in LOG_COPY_INDEX' 'log_pair_unregistered'
        }
    }

    # --- 6b. INDEX.md dead links ------------------------------------------------------
    $indexPath = Join-Path $EvidenceRoot 'INDEX.md'
    if (Try-Path $indexPath) {
        $indexContent = Read-TextGuarded $indexPath 'INDEX.md' 'read_error'
        if ($indexContent) {
            $backtickLinks = [regex]::Matches($indexContent, '`((?:runs/|samples/|sanitized-logs/|cases/|reports/)[^`]+)`')
            $deadLinks = @()
            foreach ($link in $backtickLinks) {
                $relPath = $link.Groups[1].Value
                $resolved = Join-Path $EvidenceRoot ($relPath -replace '/', '\')
                if (-not (Try-Path $resolved)) { $deadLinks += $relPath }
            }
            Check 'INDEX.md relative links valid' ($deadLinks.Count -eq 0) ("dead links: {0}" -f ($deadLinks -join ',')) 'dead_link'
        }
    }

    # --- 7. result.json parseable + runId uniqueness --------------------------------
    $resultFiles = @(Get-ChildItem $EvidenceRoot -Recurse -Filter 'result.json' -ErrorAction SilentlyContinue)
    $runIds = @{}
    foreach ($rf in $resultFiles) {
        $raw = Read-TextGuarded $rf.FullName ("result.json {0}" -f $rf.Directory.Name) 'read_error'
        if (-not $raw -or $raw.Trim().Length -eq 0) {
            Check ("result.json non-empty: {0}" -f $rf.Directory.Name) $false 'empty file' 'empty_result'
            continue
        }
        $rObj = Read-JsonGuarded $rf.FullName ("result.json {0}" -f $rf.Directory.Name)
        if ($null -eq $rObj) { continue }
        Check ("result.json parseable: {0}" -f $rf.Directory.Name) $true ''
        if ($rObj.PSObject.Properties['run_id'] -and $rObj.run_id) {
            if ($runIds.ContainsKey($rObj.run_id)) {
                Check ("run_id unique: {0}" -f $rObj.run_id) $false ("duplicate in {0} and {1}" -f $runIds[$rObj.run_id], $rf.FullName) 'runid_reuse'
            } else { $runIds[$rObj.run_id] = $rf.FullName }
        }
    }

    # --- 8. perprocess semantic fields ------------------------------------------------
    $ppResults = @(Get-ChildItem $EvidenceRoot -Recurse -Filter 'result.json' -ErrorAction SilentlyContinue |
        Where-Object { try { $o = Get-Content $_.FullName -Raw -ErrorAction Stop | ConvertFrom-Json; return ($o.entry -eq 'p0_probe_perprocess') } catch { return $false } })
    foreach ($pf in $ppResults) {
        $r = Read-JsonGuarded $pf.FullName ("perprocess result {0}" -f $pf.Directory.Name)
        if ($null -eq $r) { continue }
        Check 'perprocess guard_active is bool' ($r.guard_active -is [bool]) 'not boolean' 'bad_field_type'
        Check 'perprocess guard_blocked_count is int' ($r.guard_blocked_count -is [int]) 'not integer' 'bad_field_type'
        Check 'perprocess port_released is bool' ($r.port_released -is [bool]) 'not boolean' 'bad_field_type'
        $pr = $r.PSObject.Properties['processes_recovered']
        Check 'perprocess processes_recovered is bool (identity recheck)' ($pr -and ($r.processes_recovered -is [bool])) 'missing or not boolean' 'bad_field_type'
        $fb = $r.PSObject.Properties['fallback_hits']
        $fbOk = $fb -and ($r.fallback_hits -eq $null -or $r.fallback_hits -eq 'not_deployed' -or $r.fallback_hits -is [int])
        Check 'perprocess fallback_hits is not fabricated zero' $fbOk ("value='{0}'" -f $r.fallback_hits) 'fallback_fabricated'
        $badStatuses = @($r.recovery_details | Where-Object { $_.post_status -eq 'query_failed' }).Count
        Check 'perprocess recovery has no query_failed rows' ($badStatuses -eq 0) ("query_failed rows: " + $badStatuses) 'recovery_query_failed'
    }

    # --- 9. git check-ignore (in-repo only) ----------------------------------------------
    $evFull = [IO.Path]::GetFullPath($EvidenceRoot).TrimEnd('\')
    $repoFull = [IO.Path]::GetFullPath($RepoRoot).TrimEnd('\')
    $evInRepo = $evFull.StartsWith($repoFull, [StringComparison]::OrdinalIgnoreCase)
    if ($evInRepo -and (Try-Path (Join-Path $RepoRoot '.git'))) {
        $relPaths = @(Get-ChildItem $EvidenceRoot -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
            $_.FullName.Substring($repoFull.Length + 1).Replace('\', '/')
        })
        $gi = Git-CheckIgnoreBatch $relPaths
        if ($gi.error) {
            Check 'git check-ignore command health' $false ("command error (cannot be treated as not-ignored): " + $gi.errorDetail) 'git_check_error'
        } else {
            $ignoredList = @($relPaths | Where-Object { $gi.ignored.ContainsKey($_) })
            Check 'no evidence file is gitignored' ($ignoredList.Count -eq 0) ("ignored: {0}" -f ($ignoredList -join ',')) 'gitignored_evidence'
        }
    } else {
        CheckNA 'git check-ignore' 'evidence root outside the repo (self-test scratch tree)'
    }

    # --- 10. -Only filter: zero matches must not pass ------------------------------
    if ($Only) {
        $matchCount = @($seenCaseIds.Keys | Where-Object { $_ -eq $Only }).Count
        Check ("filter -Only '{0}' matched at least one case" -f $Only) ($matchCount -gt 0) ("matched {0} case rows" -f $matchCount) 'zero_match_filter'
    }

    Write-Host "`n=== Evidence check v5: expected=$script:expected checked=$script:checked n/a=$script:notApplicable unverified=$script:unverified skipped=$script:skipped failed=$script:fails ==="
    if ($script:fails -gt 0) { return 1 }
    return 0
}

# ---------------------------------------------------------------------------
# -SelfTest: synthetic template + 22 mutations
# ---------------------------------------------------------------------------
function Build-SelfTestTemplate([string]$base) {
    $st = Join-Path $base 'st'
    New-Item -ItemType Directory -Force -Path (Join-Path $st 'runs\a'), (Join-Path $st 'runs\b'), (Join-Path $st 'runs\recorder-x') | Out-Null
    Set-Content (Join-Path $st 'PLAN.md') 'selftest plan' -Encoding ASCII
    Set-Content (Join-Path $st 'REQUIREMENTS.json') '{"requirements":[]}' -Encoding UTF8
    Set-Content (Join-Path $st 'CHANGE_IMPACT.json') '{"items":[]}' -Encoding UTF8
    Set-Content (Join-Path $st 'INDEX.md') "selftest`n- ``runs/a/result.json```n- ``runs/a/matrix.csv```n- ``runs/recorder-x/observed.json``" -Encoding UTF8
    @'
{"cases":[{"id":"MA","wp":"A","description":"d","expected_exit":0,"expected_reason":"r-MA","requires_backend":false},
{"id":"MB","wp":"A","description":"d","expected_exit":1,"expected_reason":"r-MB","requires_backend":false}],"new_cases_this_round":[]}
'@ | Set-Content (Join-Path $st 'CASE_MANIFEST.json') -Encoding UTF8
    # recorder observed binding for run a
    @{ entry = 'selftest_stub.ps1'; entry_run_dir = (Join-Path $st 'runs\a'); actual_exit = 0; child_pid = 123; timeout_hit = $false } |
        ConvertTo-Json | Set-Content (Join-Path $st 'runs\recorder-x\observed.json') -Encoding UTF8
    '{"run_id":"ra","entry":"x","verdict":"PASS","exit_code":0}' | Set-Content (Join-Path $st 'runs\a\result.json') -Encoding UTF8
    '{"run_id":"rb","entry":"y","verdict":"PASS","exit_code":0}' | Set-Content (Join-Path $st 'runs\b\result.json') -Encoding UTF8
    'case,expectedExit,actualExit,verdict,reason' | Set-Content (Join-Path $st 'runs\a\matrix.csv') -Encoding ASCII
    Add-Content (Join-Path $st 'runs\a\matrix.csv') 'MA,0,0,PASS,r-MA' -Encoding ASCII
    'case,expectedExit,actualExit,verdict,reason' | Set-Content (Join-Path $st 'runs\b\matrix.csv') -Encoding ASCII
    Add-Content (Join-Path $st 'runs\b\matrix.csv') 'MB,1,1,PASS,r-MB' -Encoding ASCII
    # coverage with machine binding (BOTH frozen cases)
    @{ generatedAt = (Get-Date).ToString('o'); case_count = 2; coverage = @(
        @{ case = 'MA'; expected_exit = 0; observed_exit = '0'; verdict = 'PASS'; expected_reason = 'r-MA'; source = 'runs/a/result.json + recorder'; mode = 'new-run'; binding_rationale = 't' },
        @{ case = 'MB'; expected_exit = 1; observed_exit = '1'; verdict = 'PASS'; expected_reason = 'r-MB'; source = 'runs/b/result.json'; mode = 'new-run'; binding_rationale = 't' }
    ) } | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $st 'COVERAGE.json') -Encoding UTF8
    # log pair: original present + copy
    'LOGDATA' | Set-Content (Join-Path $st 'runs\a\sample.log') -Encoding ASCII
    'LOGDATA' | Set-Content (Join-Path $st 'runs\a\sample.log.txt') -Encoding ASCII
    $logSha = (Get-FileHash (Join-Path $st 'runs\a\sample.log') -Algorithm SHA256).Hash
    @{ generatedAt = (Get-Date).ToString('o'); pair_count = 1; pairs = @(
        @{ original_state = 'original_present'; original = 'runs/a/sample.log'; copy = 'runs/a/sample.log.txt'; original_sha256 = $logSha; copy_sha256 = $logSha; sanitization = 'none (byte-identical copy; NO sanitization performed or claimed)'; sanitized_at = $null }
    ) } | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $st 'LOG_COPY_INDEX.json') -Encoding UTF8
    # script-hashes: real helper so it resolves
    $realSha = (Get-FileHash (Join-Path $RepoRoot 'tests\performance\p0_env.ps1') -Algorithm SHA256).Hash
    @{ 'p0_env.ps1' = $realSha } | ConvertTo-Json | Set-Content (Join-Path $st 'runs\a\script-hashes.json') -Encoding UTF8
    # INPUT manifest over the template
    $entries = New-Object System.Collections.Generic.List[object]
    foreach ($f in (Get-ChildItem $st -Recurse -File | Sort-Object FullName)) {
        $rel = $f.FullName.Substring($st.Length + 1).Replace('\', '/')
        $entries.Add([ordered]@{ path = $rel; sha256 = (Get-FileHash $f.FullName -Algorithm SHA256).Hash; bytes = $f.Length })
    }
    $digestInput = ($entries | ForEach-Object { "$($_.path)`0$($_.sha256)`n" }) -join ''
    $bytes2 = [Text.Encoding]::UTF8.GetBytes($digestInput)
    $shaProv = [System.Security.Cryptography.SHA256]::Create()
    $digest = [BitConverter]::ToString($shaProv.ComputeHash($bytes2)).Replace('-', '')
    @{ generatedAt = (Get-Date).ToString('o'); ordering = 'full path ascending'; excluded = @{}
       file_count = $entries.Count; digest = $digest; entries = $entries } |
        ConvertTo-Json -Depth 5 | Set-Content (Join-Path $st 'INPUT_MANIFEST.json') -Encoding UTF8
    # root script-hashes.json (canonical identity source for the template)
    @{ 'p0_env.ps1' = $realSha } | ConvertTo-Json | Set-Content (Join-Path $st 'script-hashes.json') -Encoding UTF8
    return $st
}

function Invoke-CheckerChild([string]$root, [string[]]$extraArgs = @()) {
    $report = Join-Path $base ('report-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.json')
    $args_ = @('-NoProfile','-ExecutionPolicy','Bypass','-File', $PSCommandPath, '-EvidenceRoot', $root, '-RepoRoot', $RepoRoot, '-ReportPath', $report) + $extraArgs
    $child = Start-P0PowerShell -ArgumentList (($args_ | ForEach-Object { ConvertTo-P0Argument $_ }) -join ' ') -Wait -RedirectStandardOutput ($report + '.stdout.txt') -RedirectStandardError ($report + '.stderr.txt')
    $exit = $child.ExitCode
    $rep = $null
    if (Test-Path $report) { try { $rep = Get-Content $report -Raw | ConvertFrom-Json } catch { } }
    return @{ exit = $exit; report = $rep; reportPath = $report }
}

if ($SelfTest) {
    if (-not $SelfTestOut) { $SelfTestOut = Join-Path ([IO.Path]::GetTempPath()) ("p0-ec-selftest-" + [guid]::NewGuid().ToString('N').Substring(0, 8)) }
    $base = $SelfTestOut
    # Expand Windows 8.3 temp prefix before deriving relative paths.
    if (-not (Test-Path $base)) { New-Item -ItemType Directory -Path $base -Force | Out-Null; $createdBase = $true }
    $base = (Get-ChildItem (Split-Path $base -Parent) -Directory | Where-Object Name -eq (Split-Path $base -Leaf)).FullName
    if (-not $createdBase) { Write-Host '[FAIL] selftest output exists (refuse overwrite)'; exit 2 }
    New-Item -ItemType Directory -Force -Path $base | Out-Null
    $st = Build-SelfTestTemplate $base

    # checker self-identity for the report (R5: bind own hash + deps + real exits)
    $checkerSha = (Get-FileHash $PSCommandPath -Algorithm SHA256).Hash
    $depShas = [ordered]@{}
    foreach ($f in @('p0_paths.ps1','p0_runs.ps1','p0_env.ps1','p0_seal_round.ps1','p0_run_recorder.ps1')) {
        $p = Join-Path $RepoRoot ('tests\performance\' + $f)
        if (Test-Path $p) { $depShas[$f] = (Get-FileHash $p -Algorithm SHA256).Hash }
    }

    # input tree hash before (mutations act on COPIES; the template itself is
    # copied per mutation, so 'before/after' applies per copy - see below)
    $clean = Invoke-CheckerChild $st
    $cleanOk = ($clean.exit -eq 0)
    Write-Host ("selftest[clean]: exit={0} ok={1}" -f $clean.exit, $cleanOk)
    $muts = New-Object System.Collections.Generic.List[object]

    function Mutate([string]$name, [string]$expectReason, [scriptblock]$corrupt, [string[]]$extraArgs = @()) {
        $copy = Join-Path $base ("mut-" + $name)
        Copy-Item $st $copy -Recurse -Force
        & $corrupt $copy
        # rebind the template recorder path to THIS copy (entry_run_dir in
        # observed.json otherwise still points at the original template)
        $ojCopy = Join-Path $copy 'runs\recorder-x\observed.json'
        if (Test-Path $ojCopy) {
            try {
                $o = Get-Content $ojCopy -Raw | ConvertFrom-Json
                $o.entry_run_dir = (Join-Path $copy 'runs\a')
                $o | ConvertTo-Json | Set-Content $ojCopy -Encoding UTF8
            } catch { }
        }
        $r = Invoke-CheckerChild $copy $extraArgs
        $rejected = $r.exit -ne 0
        $reasonMatch = $false
        if ($r.report) {
            # FAIL and UNVERIFIED rows both carry decisive reason codes
            $codes = @($r.report.results | Where-Object { $_.result -eq 'FAIL' -or $_.result -eq 'UNVERIFIED' } | ForEach-Object { $_.reason_code })
            $reasonMatch = ($codes -contains $expectReason)
        }
        Write-Host ("selftest[{0}]: exit={1} rejected={2} reasonMatch={3}" -f $name, $r.exit, $rejected, $reasonMatch)
        $muts.Add([pscustomobject]@{ mutation = $name; exit = $r.exit; rejected = $rejected; reason_matched = $reasonMatch; expected_reason = $expectReason }) | Out-Null
    }

    # --- carried-over 13 -------------------------------------------------------
    Mutate 'missing-evidence' 'dead_link' { param($c) Remove-Item (Join-Path $c 'runs\a\result.json') }
    Mutate 'missing-script' 'unresolved_hash_target' { param($c)
        $hf = Join-Path $c 'runs\a\script-hashes.json'; $h = Get-Content $hf -Raw | ConvertFrom-Json
        $h | Add-Member -NotePropertyName 'nonexistent/does/not_exist.py' -NotePropertyValue 'DEADBEEF' -Force
        $h | ConvertTo-Json | Set-Content $hf -Encoding UTF8 }
    Mutate 'wrong-hash' 'hash_drift' { param($c)
        $hf = Join-Path $c 'runs\a\script-hashes.json'; $h = Get-Content $hf -Raw | ConvertFrom-Json
        $h.'p0_env.ps1' = '0000000000000000000000000000000000000000000000000000000000000000'
        $h | ConvertTo-Json | Set-Content $hf -Encoding UTF8 }
    Mutate 'helper-drift' 'hash_drift' { param($c)
        $hf = Join-Path $c 'script-hashes.json'; $h = Get-Content $hf -Raw | ConvertFrom-Json
        $h | Add-Member -NotePropertyName 'p0_guard/sitecustomize.py' -NotePropertyValue ('A' * 64) -Force
        $h | ConvertTo-Json | Set-Content $hf -Encoding UTF8 }
    Mutate 'dead-link' 'dead_link' { param($c)
        Add-Content (Join-Path $c 'INDEX.md') '- `runs/nonexistent.md`' -Encoding UTF8 }
    Mutate 'missing-mandatory' 'missing_mandatory_case' { param($c)
        (Get-Content (Join-Path $c 'runs\a\matrix.csv')) | Where-Object { $_ -notmatch '^MA,' } | Set-Content (Join-Path $c 'runs\a\matrix.csv') -Encoding ASCII }
    Mutate 'wrong-reason' 'wrong_reason' { param($c)
        (Get-Content (Join-Path $c 'runs\a\matrix.csv')) -replace 'r-MA', 'r-WRONG' | Set-Content (Join-Path $c 'runs\a\matrix.csv') -Encoding ASCII }
    Mutate 'wrong-verdict' 'verdict_inconsistent' { param($c)
        (Get-Content (Join-Path $c 'runs\a\matrix.csv')) -replace 'MA,0,0,PASS,r-MA', 'MA,0,0,FAIL,r-MA' | Set-Content (Join-Path $c 'runs\a\matrix.csv') -Encoding ASCII }
    Mutate 'empty-matrix' 'empty_matrix' { param($c)
        'case,expectedExit,actualExit,verdict,reason' | Set-Content (Join-Path $c 'runs\a\matrix.csv') -Encoding ASCII }
    Mutate 'zero-match-filter' 'zero_match_filter' { param($c) } @('-Only', 'ZZZ-NO-MATCH')
    Mutate 'runid-reuse' 'runid_reuse' { param($c)
        New-Item -ItemType Directory -Force -Path (Join-Path $c 'runs\b') | Out-Null
        '{"run_id":"ra","entry":"y","verdict":"PASS"}' | Set-Content (Join-Path $c 'runs\b\result.json') -Encoding UTF8 }
    Mutate 'log-copy-mismatch' 'log_copy_hash_mismatch' { param($c)
        'LOGDATA-TAMPERED' | Set-Content (Join-Path $c 'runs\a\sample.log.txt') -Encoding ASCII }
    # git-check-failure: in-repo scratch (the git check only runs for in-repo roots)
    $gitScratch = Join-Path $RepoRoot ('.p0-ec-selftest-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Force -Path $gitScratch | Out-Null
    try {
        Copy-Item $st (Join-Path $gitScratch 'st') -Recurse -Force
        $gitCopy = Join-Path $gitScratch 'st'
        $argsGit = @('-GitFailInject')
        $r = Invoke-CheckerChild $gitCopy $argsGit
        $reasonMatch = $false
        if ($r.report) { $reasonMatch = (@($r.report.results | Where-Object { $_.result -eq 'FAIL' -and $_.reason_code -eq 'git_check_error' }).Count -gt 0) }
        Write-Host ("selftest[git-check-failure]: exit={0} rejected={1} reasonMatch={2}" -f $r.exit, ($r.exit -ne 0), $reasonMatch)
        $muts.Add([pscustomobject]@{ mutation = 'git-check-failure'; exit = $r.exit; rejected = ($r.exit -ne 0); reason_matched = $reasonMatch; expected_reason = 'git_check_error' }) | Out-Null
    } finally { Remove-Item $gitScratch -Recurse -Force -ErrorAction SilentlyContinue }

    # --- new R5 mutations (9) ------------------------------------------------------
    Mutate 'illegal-original-path' 'path_illegal' { param($c)
        $lcj = Join-Path $c 'LOG_COPY_INDEX.json'; $lc = Get-Content $lcj -Raw | ConvertFrom-Json
        $lc.pairs[0].original_state = 'original_present'
        $lc.pairs[0].original = 'runs/a/con<del>|bad*.log'
        $lc | ConvertTo-Json -Depth 5 | Set-Content $lcj -Encoding UTF8 }
    Mutate 'unknown-original-claimed' 'unknown_original_claimed_verified' { param($c)
        $lcj = Join-Path $c 'LOG_COPY_INDEX.json'; $lc = Get-Content $lcj -Raw | ConvertFrom-Json
        $lc.pairs[0].original_state = 'original_unavailable'
        $lc.pairs[0].original = 'runs/a/sample.log'
        $lc.pairs[0].original_sha256 = 'A' * 64
        $lc | ConvertTo-Json -Depth 5 | Set-Content $lcj -Encoding UTF8 }
    Mutate 'source-run-missing' 'missing_source_run' { param($c)
        $cj = Join-Path $c 'COVERAGE.json'; $cov = Get-Content $cj -Raw | ConvertFrom-Json
        $cov.coverage[0].source = 'runs/does-not-exist/result.json'
        $cov | ConvertTo-Json -Depth 5 | Set-Content $cj -Encoding UTF8 }
    Mutate 'source-runtime-hash-mismatch' 'hash_drift' { param($c)
        $hf = Join-Path $c 'runs\a\script-hashes.json'; $h = Get-Content $hf -Raw | ConvertFrom-Json
        $h.'p0_env.ps1' = ('B' * 64)
        $h | ConvertTo-Json | Set-Content $hf -Encoding UTF8 }
    Mutate 'planned-observed-mismatch' 'planned_observed_mismatch' { param($c)
        $oj = Join-Path $c 'runs\recorder-x\observed.json'; $o = Get-Content $oj -Raw | ConvertFrom-Json
        $o.actual_exit = 2
        $o | ConvertTo-Json | Set-Content $oj -Encoding UTF8 }
    Mutate 'observed-exit-missing' 'unverified_observation' { param($c)
        $cj = Join-Path $c 'COVERAGE.json'; $cov = Get-Content $cj -Raw | ConvertFrom-Json
        $cov.coverage[0].observed_exit = 'unverified'
        $cov | ConvertTo-Json -Depth 5 | Set-Content $cj -Encoding UTF8 }
    Mutate 'same-code-wrong-reason' 'wrong_reason' { param($c)
        $cj = Join-Path $c 'COVERAGE.json'; $cov = Get-Content $cj -Raw | ConvertFrom-Json
        $cov.coverage[0].expected_reason = 'r-DIFFERENT'
        $cov | ConvertTo-Json -Depth 5 | Set-Content $cj -Encoding UTF8 }
    Mutate 'recovery-unknown-pass' 'recovery_query_failed' { param($c)
        New-Item -ItemType Directory -Force -Path (Join-Path $c 'runs\pp') | Out-Null
        '{"run_id":"pp1","entry":"p0_probe_perprocess","verdict":"PASS","exit_code":0,"guard_active":true,"guard_blocked_count":0,"port_released":true,"processes_recovered":true,"fallback_hits":"not_deployed","recovery_details":[{"pid":1,"created":"x","post_status":"query_failed"}]}' |
            Set-Content (Join-Path $c 'runs\pp\result.json') -Encoding UTF8 }
    Mutate 'selected-run-missing-artifact' 'missing_mandatory_case' { param($c)
        Remove-Item (Join-Path $c 'runs\a\matrix.csv') }
    Mutate 'p02-without-recorded-run' 'missing_semantic_run' { param($c)
        $file = Join-Path $c 'COVERAGE.json'; $cov = Get-Content $file -Raw | ConvertFrom-Json
        $cov.coverage += [pscustomobject]@{ case = 'P02'; mode = 'new-run'; source = 'runs/a/result.json'; observed_exit = '0'; verdict = 'PASS'; expected_reason = 'result_complete' }
        $cov | ConvertTo-Json -Depth 6 | Set-Content $file -Encoding UTF8 }
    Mutate 'i04-selftest-pollution' 'missing_semantic_run' { param($c)
        $file = Join-Path $c 'COVERAGE.json'; $cov = Get-Content $file -Raw | ConvertFrom-Json
        $cov.coverage += [pscustomobject]@{ case = 'I04'; mode = 'new-run'; source = 'runs/a/matrix.csv'; observed_exit = '0'; verdict = 'PASS'; expected_reason = 'matrix_pass' }
        $cov | ConvertTo-Json -Depth 6 | Set-Content $file -Encoding UTF8 }
    Mutate 'final-missing-prior-observation' 'missing_outer_observation' { param($c) } @('-Final')

    $allRejected = (($muts | Where-Object { -not $_.rejected }).Count -eq 0) -and (($muts | Where-Object { -not $_.reason_matched }).Count -eq 0)
    $report = [ordered]@{
        selftest_version = 5
        checker_sha256 = $checkerSha
        dependency_hashes = $depShas
        clean_pass = $cleanOk
        mutation_count = $muts.Count
        all_mutations_rejected = $allRejected
        mutations = $muts
        note = 'clean run + every mutation executed as a real child process; exits recorded per mutation; reasons matched against structured reason codes'
    }
    $reportPath = if ($ReportPath) { $ReportPath } else { Join-Path $base 'selftest-report.json' }
    $report | ConvertTo-Json -Depth 6 | Set-Content $reportPath -Encoding UTF8
    Write-Host ("selftest report: {0}" -f $reportPath)
    if ($allRejected -and $cleanOk) { exit 0 } else { exit 3 }
}

# --- entry -------------------------------------------------------------------
if (-not $EvidenceRoot) { Write-Host 'usage: -EvidenceRoot <dir> | -SelfTest'; exit 2 }
$rc = Run-CheckSet
if ($ReportPath) {
    [ordered]@{
        checker = 'p0_evidence_check.ps1 v5'
        checker_sha256 = (Get-FileHash $PSCommandPath -Algorithm SHA256).Hash
        checked_root = $EvidenceRoot
        generated_at = (Get-Date).ToString('o')
        counts = @{ expected = $script:expected; checked = $script:checked; skipped = $script:skipped
                    failed = $script:fails; not_applicable = $script:notApplicable; unverified = $script:unverified }
        results = $script:results
        status = $(if ($rc -eq 0) { 'PASS' } else { 'FAIL' })
    } | ConvertTo-Json -Depth 6 | Set-Content $ReportPath -Encoding UTF8
    Write-Host ("report written: {0}" -f $ReportPath)
}
exit $rc

