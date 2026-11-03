# Evidence sealing for P0 final closure (ASCII only, PS 5.1 safe)
# F6: seal the two synthetic sample PDFs from the v2 formal run's isolated
#     work dir (supplementary manifest with time/source/boundary notes).
# F3/F6: archive sanitized copies of key logs (download-attempt evidence,
#     guard logs, harness logs); originals stay read-only in temp roots.
# Output: docs/verification/native-desktop/final-closure-<stamp>/

param(
    [string]$RepoRoot = 'D:\paper\PDFMathTranslate-next',
    [string]$V2TempRoot = 'C:\Users\admin\AppData\Local\Temp\pdf2zh-p0-20260928-120431-6756',
    [string]$V1ProbeTempRoot = 'C:\Users\admin\AppData\Local\Temp\pdf2zh-probe-pp-20260928-121027-56680'
)

$ErrorActionPreference = 'Stop'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$ev = Join-Path $RepoRoot "docs\verification\native-desktop\final-closure-$stamp"
New-Item -ItemType Directory -Force -Path (Join-Path $ev 'samples'), (Join-Path $ev 'sanitized-logs') | Out-Null

function Sha([string]$p) { if (Test-Path $p) { return (Get-FileHash $p -Algorithm SHA256).Hash } return $null }

# --- 1. seal samples (supplementary; not a re-run) ----------------------------
$sampleManifest = [ordered]@{
    sealedAt = (Get-Date).ToString('o')
    sourceRoot = $V2TempRoot + '\work'
    sourceNote = 'files were generated in place during formal baseline run run-v2-20260928-120431 (2026-09-28 12:04); copied now as supplementary sealing - this does NOT retroactively attach hashes to the sampling moment (F6 boundary)'
    expectedFromFinalReview = [ordered]@{
        'p0-sample-1p.pdf' = '8864D83D85AB29B507D98B08EAEDF892B586D259C052B266E48C31990B5708B0'
        'p0-sample-20p.pdf' = '195BDB79BFE272EBFF18780A0F154D32E01FDCAFCEE87A6F5D84F9ABD5FB37D5'
    }
    files = [ordered]@{}
}
foreach ($s in @('p0-sample-1p.pdf', 'p0-sample-20p.pdf')) {
    $src = Join-Path $V2TempRoot ("work\" + $s)
    if (Test-Path $src) {
        Copy-Item $src (Join-Path $ev ('samples\' + $s)) -Force
        $sampleManifest.files[$s] = [ordered]@{
            sha256 = Sha (Join-Path $ev ('samples\' + $s))
            bytes = (Get-Item (Join-Path $ev ('samples\' + $s))).Length
            matchesFinalReview = ((Sha (Join-Path $ev ('samples\' + $s))) -eq $sampleManifest.expectedFromFinalReview[$s])
        }
    } else {
        $sampleManifest.files[$s] = '<missing at sealing time>'
    }
}
$sampleManifest | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $ev 'samples\supplementary-manifest.json') -Encoding UTF8
Write-Host "[samples] sealed -> $(Join-Path $ev 'samples')"

# --- 2. sanitized log archival -------------------------------------------------
$idx = New-Object System.Collections.Generic.List[string]
$idx.Add('# Sanitized log archive (P0 final closure) - generated ' + (Get-Date).ToString('o'))
$idx.Add('# Sanitization: absolute machine paths replaced with <installroot>/<isolated-root>; content otherwise verbatim.')
$idx.Add('# Originals remain (read-only) in their temp roots; *.log stays gitignored, these copies are .log.txt.')

function Archive-Log([string]$src, [string]$name, [string]$origin) {
    if (-not (Test-Path $src)) { $idx.Add(("MISSING`t" + $name + "t(origin: " + $origin + ") - file absent at sealing time")); return }
    $raw = Get-Content $src -Raw -ErrorAction SilentlyContinue
    $san = $raw -replace [regex]::Escape('D:\paper\pdf2zh-install-test'), '<installroot>' `
                  -replace [regex]::Escape('D:\paper\PDFMathTranslate-next'), '<repo>' `
                  -replace [regex]::Escape('C:\Users\admin\AppData\Local\Temp'), '%TEMP%'
    $dst = Join-Path $ev ('sanitized-logs\' + $name + '.txt')
    Set-Content -Path $dst -Value $san -Encoding UTF8
    $idx.Add(("OK`t" + $name + "torigin: " + $origin + "toriginal-sha256: " + (Sha $src) + "tsealed-copy-sha256: " + (Sha $dst)))
}

# v1 per-process probe backend log = F3 download-attempt evidence
Archive-Log (Join-Path $V1ProbeTempRoot 'backend.log') 'backend-v1-perprocess-download-evidence.log' ($V1ProbeTempRoot + '\backend.log')
# v2 formal run harness + backend logs
$runDirV2 = Join-Path $RepoRoot 'docs\verification\native-desktop\run-v2-20260928-120431'
if (Test-Path $runDirV2) {
    Get-ChildItem $runDirV2 -Filter '*.log' -ErrorAction SilentlyContinue | ForEach-Object {
        Archive-Log $_.FullName ('v2-' + $_.Name) $_.FullName
    }
}
# v2 trial run logs
$runDirTrial = Get-ChildItem (Join-Path $RepoRoot 'docs\verification\native-desktop') -Directory -Filter 'run-v2-20260928-115520' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($runDirTrial) {
    Get-ChildItem $runDirTrial.FullName -Filter '*.log' -ErrorAction SilentlyContinue | ForEach-Object {
        Archive-Log $_.FullName ('v2trial-' + $_.Name) $_.FullName
    }
}
$idx | Set-Content (Join-Path $ev 'sanitized-logs\SANITIZED-LOGS-INDEX.txt') -Encoding UTF8
Write-Host ("[logs] archived -> " + (Join-Path $ev 'sanitized-logs'))
Write-Host ("[evidence] " + $ev)
exit 0
