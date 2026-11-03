# One layout resolver for recorder -> entry-run -> result, shared by seal/checker.
function Get-P0RecordedRuns([string]$EvidenceRoot, [string]$EntryName) {
    $runsRoot = [IO.Path]::GetFullPath((Join-Path $EvidenceRoot 'runs')).TrimEnd('\') + '\'
    foreach ($rd in (Get-ChildItem -LiteralPath $runsRoot -Directory -Filter 'recorder-*' -ErrorAction SilentlyContinue | Sort-Object Name -Descending)) {
        $oj = Join-Path $rd.FullName 'observed.json'
        if (-not (Test-Path -LiteralPath $oj)) { throw "missing recorder observation: $oj" }
        $o = Get-Content -LiteralPath $oj -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ((Split-Path "$($o.entry)" -Leaf) -ne $EntryName) { continue }
        $entryRoot = [IO.Path]::GetFullPath((Join-Path $rd.FullName 'entry-run'))
        if ($entryRoot -ne [IO.Path]::GetFullPath("$($o.entry_run_dir)")) { throw 'recorder entry-run mismatch' }
        if (-not $entryRoot.StartsWith($runsRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'recorder outside round' }
        if (-not $o.PSObject.Properties['actual_exit'] -or $null -eq $o.actual_exit) { throw 'recorder exit missing' }
        if ($EntryName -eq 'p0_baseline.ps1') {
            $dirs = @(Get-ChildItem -LiteralPath $entryRoot -Directory -Filter 'run-v3-*' -ErrorAction Stop)
            if ($dirs.Count -ne 1) { throw 'baseline recorder must bind exactly one run' }
            $resultDir = $dirs[0]
        } else { $resultDir = Get-Item -LiteralPath $entryRoot -ErrorAction Stop }
        if (-not (Test-Path -LiteralPath (Join-Path $resultDir.FullName 'result.json'))) { throw 'recorded run result missing' }
        $resultDir | Add-Member -NotePropertyName P0Observation -NotePropertyValue $o -Force
        $resultDir
    }
}
function Get-P0MatrixRuns([string]$EvidenceRoot) {
    $candidates = @(Get-ChildItem (Join-Path $EvidenceRoot 'runs') -Directory -Filter 'matrix-*' -ErrorAction SilentlyContinue)
    foreach ($rd in (Get-ChildItem (Join-Path $EvidenceRoot 'runs') -Directory -Filter 'recorder-*' -ErrorAction SilentlyContinue)) {
        $oj = Join-Path $rd.FullName 'observed.json'
        if (-not (Test-Path $oj)) { continue }
        $o = Get-Content $oj -Raw | ConvertFrom-Json
        if ((Split-Path "$($o.entry)" -Leaf) -eq 'p0_negative_tests.ps1') {
            $candidates += Get-Item (Join-Path $rd.FullName 'entry-run') -ErrorAction Stop
        }
    }
    $candidates | Where-Object {
        if ($_.Name -like '*selftest*' -or $_.Name -like '*reuse-probe*') { return $false }
        $identity = Join-Path $_.FullName 'matrix-identity.json'
        if (-not (Test-Path $identity)) { return $false }
        $kind = Get-Content $identity -Raw | ConvertFrom-Json
        return ($kind.kind -eq 'acceptance' -and -not $kind.only -and (Test-Path (Join-Path $_.FullName 'cases\matrix.csv')))
    } | Sort-Object FullName
}
