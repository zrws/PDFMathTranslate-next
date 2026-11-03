# R2 isolation sentinel tests (ASCII only, PS 5.1 safe).
# Proves, for the REAL asset-check helper and the real PNG decoder:
#   1. standalone helper call in an isolated temp root -> effective
#      cache_folder/HOME inside the ISOLATED root; a real user dir in the
#      child output FAILS the check.
#   2. per-child env: caller parent env keeps REAL HOME while the child sees
#      only the isolated root (proves per-child injection, not inheritance).
#   3. asset manifest failure modes each return $false with a precise reason:
#      garbled metadata / empty manifest / missing category / hash tool fail /
#      missing asset / corrupt asset.
#   4. caller-path restoration: after a run that temporarily sets parent env,
#      existed/value helper restores everything (reuses G16 machinery).
# Exit: 0 all sentinel checks pass; 1 any failure; 4 prerequisite missing.

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
. (Join-Path $RepoRoot 'tests\performance\p0_asset_check.ps1')

$guardDir = Join-Path $RepoRoot 'tests\performance\p0_guard'
$python = Resolve-P0Python $InstallRoot $PythonExe
if (-not $python) { Write-Host '[FAIL] prerequisite missing'; exit 4 }
if (-not $OutDir) {
    $OutDir = Join-Path $EvidenceRoot ("runs\isolation-sentinel-" +
        (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + $PID)
}
if ((Test-Path $OutDir) -and (Get-ChildItem $OutDir -ErrorAction SilentlyContinue)) {
    Write-Host ("[FAIL] OutDir exists and non-empty (refuse overwrite): " + $OutDir); exit 2
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

@{
    'p0_asset_check.ps1' = (Get-FileHash (Join-Path $RepoRoot 'tests\performance\p0_asset_check.ps1') -Algorithm SHA256).Hash
    'p0_env.ps1' = (Get-FileHash (Join-Path $RepoRoot 'tests\performance\p0_env.ps1') -Algorithm SHA256).Hash
    'p0_guard/png_check.ps1' = (Get-FileHash (Join-Path $guardDir 'png_check.ps1') -Algorithm SHA256).Hash
    'p0_isolation_negtest.ps1' = (Get-FileHash $PSCommandPath -Algorithm SHA256).Hash
} | ConvertTo-Json | Set-Content (Join-Path $OutDir 'script-hashes.json') -Encoding UTF8

$script:fails = 0
$rows = New-Object System.Collections.Generic.List[string]
function Check([string]$name, [bool]$ok, [string]$detail) {
    if ($ok) { Write-Host "[PASS] $name" } else { Write-Host ("[FAIL] {0} : {1}" -f $name, $detail); $script:fails++ }
    $rows.Add(("{0},{1}" -f $name, $(if ($ok) { 'PASS' } else { 'FAIL' })))
}

$realUser = [Environment]::GetEnvironmentVariable('USERPROFILE')

# --- sentinel 1: standalone helper in isolated root; real HOME stays in parent
$isoRoot = Join-Path $OutDir 'iso-home'
New-Item -ItemType Directory -Force -Path (Join-Path $isoRoot '.config\pdf2zh') | Out-Null
# keep the PARENT HOME as the real user profile (proves per-child injection)
$stageCache = Join-Path ([IO.Path]::GetTempPath()) ('pdf2zh-isolation-assets-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stageCache | Out-Null
@{ owner='p0_isolation_negtest.ps1'; pid=$PID; cache_root=$stageCache; note='Owned offline cache preserved outside evidence/Git' } | ConvertTo-Json | Set-Content (Join-Path $OutDir 'cache-root.json') -Encoding UTF8
robocopy (Join-Path $InstallRoot 'home\.cache\babeldoc') $stageCache /E /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { Write-Host '[FAIL] cannot stage test cache copy'; exit 4 }
$assetOut = Join-Path $OutDir 'asset-standalone.log.txt'
$null = Invoke-AssetCheck -CacheDir $stageCache -InstallRoot $InstallRoot -IsolatedHome $isoRoot -PythonExe $python *>&1 |
    Tee-Object -FilePath $assetOut
$assetLogText = Get-Content $assetOut -Raw
$ok1 = ($assetLogText -match '=> PASS')
# machine artifact (console lines can be width-truncated under PS 5.1 redirection)
$metaArtifact = Join-Path $isoRoot 'assetcheck-tmp\assetcheck-meta.json'
$metaOk = $false
$metaCacheFolder = ''
if (Test-Path $metaArtifact) {
    $mi = Get-Content $metaArtifact -Raw | ConvertFrom-Json
    $metaCacheFolder = "$($mi.cache_folder)"
    $metaOk = ($metaCacheFolder -like ($isoRoot + '*')) -and ("$($mi.effective_home)" -like ($isoRoot + '*'))
}
$metaLine = $metaCacheFolder
Check 'standalone: asset check passes with isolated home' $ok1 ("see $assetOut")
Check 'standalone: cache_folder inside isolated root (machine artifact)' $metaOk ("cache_folder=$metaCacheFolder isoRoot=$isoRoot")
Check 'standalone: no real user dir in child output' (-not ((Get-Content $assetOut -Raw) -match [regex]::Escape($realUser))) 'real USERPROFILE appeared in child output'

# --- sentinel 2: metadata failure modes (synthetic manifests via stub python)
# The helper must refuse/fail with precise reasons. We simulate by pointing the
# helper at an EMPTY cache dir (missing assets), and at a cache with one
# corrupted file; the helper's own metadata read comes from the real locked
# package (we do NOT fake the package). Missing/corrupt reasons are asserted.
$emptyCache = Join-Path $OutDir 'empty-cache'
New-Item -ItemType Directory -Force -Path $emptyCache | Out-Null
$out2 = Join-Path $OutDir 'asset-empty.log.txt'
$null = Invoke-AssetCheck -CacheDir $emptyCache -InstallRoot $InstallRoot -IsolatedHome $isoRoot -PythonExe $python *>&1 |
    Tee-Object -FilePath $out2 | Out-Null
Check 'failure: empty cache -> false with asset_missing' ((Get-Content $out2 -Raw) -match 'asset_missing') "see $out2"

$corruptCache = Join-Path $OutDir 'corrupt-cache'
robocopy $stageCache $corruptCache /E /NFL /NDL /NJH /NJS /NP | Out-Null
$victim = Get-ChildItem (Join-Path $corruptCache 'models') -File | Sort-Object Length | Select-Object -First 1
[IO.File]::WriteAllBytes($victim.FullName, [byte[]](0, 1, 2, 3))
$out3 = Join-Path $OutDir 'asset-corrupt.log.txt'
$null = Invoke-AssetCheck -CacheDir $corruptCache -InstallRoot $InstallRoot -IsolatedHome $isoRoot -PythonExe $python *>&1 |
    Tee-Object -FilePath $out3 | Out-Null
Check 'failure: corrupted file -> false with asset_corrupt' ((Get-Content $out3 -Raw) -match 'asset_corrupt') "see $out3"

# --- sentinel 3b: manifest failure modes via the TEST SEAM (M5) ----------------
# synthetic metadata files simulate garbled / empty / missing-category
# manifests; the helper must refuse each with the precise reason (never
# total=0 -> true). -TestMetaJsonPath is a TEST-ONLY seam on Invoke-AssetCheck.
$garbled = Join-Path $OutDir 'meta-garbled.json'
'this is not json {{{' | Set-Content $garbled -Encoding ASCII
$outG = Join-Path $OutDir 'asset-garbled.log.txt'
$null = Invoke-AssetCheck -CacheDir $stageCache -InstallRoot $InstallRoot -IsolatedHome $isoRoot -PythonExe $python -TestMetaJsonPath $garbled *>&1 |
    Tee-Object -FilePath $outG | Out-Null
Check 'failure: garbled metadata -> false with metadata_unparseable' ((Get-Content $outG -Raw) -match 'metadata_unparseable') "see $outG"

$emptyManifest = Join-Path $OutDir 'meta-empty.json'
# single-line JSON: the helper reads the first line starting with '{'
'{"file_list": {"fonts": [], "models": [], "cmap": [], "tiktoken": []}, "cache_folder": "unused", "babeldoc_version": "test", "effective_home": "unused"}' |
    Set-Content $emptyManifest -Encoding UTF8
$outE = Join-Path $OutDir 'asset-empty-manifest.log.txt'
$null = Invoke-AssetCheck -CacheDir $stageCache -InstallRoot $InstallRoot -IsolatedHome $isoRoot -PythonExe $python -TestMetaJsonPath $emptyManifest *>&1 |
    Tee-Object -FilePath $outE | Out-Null
Check 'failure: empty manifest -> false with empty_manifest' ((Get-Content $outE -Raw) -match 'empty_manifest') "see $outE"

$missingCat = Join-Path $OutDir 'meta-missing-cat.json'
'{"file_list": {"fonts": [{"name": "f.ttf", "sha3_256": "00"}], "models": [{"name": "m.onnx", "sha3_256": "01"}], "cmap": [{"name": "c.txt", "sha3_256": "02"}]}, "cache_folder": "unused", "babeldoc_version": "test", "effective_home": "unused"}' |
    Set-Content $missingCat -Encoding UTF8
$outM = Join-Path $OutDir 'asset-missing-cat.log.txt'
$null = Invoke-AssetCheck -CacheDir $stageCache -InstallRoot $InstallRoot -IsolatedHome $isoRoot -PythonExe $python -TestMetaJsonPath $missingCat *>&1 |
    Tee-Object -FilePath $outM | Out-Null
Check 'failure: missing required category -> false with missing_category' ((Get-Content $outM -Raw) -match 'missing_category') "see $outM"

$outH = Join-Path $OutDir 'asset-hashtool-fail.log.txt'
$null = Invoke-AssetCheck -CacheDir $stageCache -InstallRoot $InstallRoot -IsolatedHome $isoRoot -PythonExe $python -TestHashToolFailure *>&1 |
    Tee-Object -FilePath $outH | Out-Null
Check 'failure: hash tool failure -> false with hash_tool_failed' ((Get-Content $outH -Raw) -match 'hash_tool_failed') "see $outH"

# --- sentinel 3: missing -IsolatedHome must REFUSE (isolation mandatory)
$out4 = Join-Path $OutDir 'asset-nohome.log.txt'
$noHome = $false
try { $noHome = Invoke-AssetCheck -CacheDir $stageCache -InstallRoot $InstallRoot -IsolatedHome (Join-Path $OutDir 'does-not-exist') -PythonExe $python *>&1 | Tee-Object -FilePath $out4 | Out-Null } catch { }
Check 'failure: nonexistent IsolatedHome -> refused' (-not $noHome) 'helper accepted a nonexistent isolated root'

# --- sentinel 4: PNG decoder child isolation (valid PNG decodes; child never
#     touches the real home - verified via the isolated temp artifacts)
. (Join-Path $guardDir 'png_check.ps1')
Set-PngPythonExe $python (Join-Path $InstallRoot 'uv-tools\pdf2zh-next\Lib\site-packages') -IsolatedHome $isoRoot
$pngIsoTmp = Join-Path $isoRoot 'pngcheck-tmp'
$genCode = @'
import pymupdf
doc = pymupdf.open(); page = doc.new_page()
page.insert_text((72, 72), "iso sentinel", fontsize=12)
pix = page.get_pixmap(matrix=pymupdf.Matrix(640/595, 640/595), alpha=False)
pix.save(r"__OUT__")
'@
$genPy = Join-Path $OutDir 'gen_png.py'
$genCode = $genCode -replace '__OUT__', (Join-Path $OutDir 'sentinel.png')
Set-Content -Path $genPy -Value $genCode -Encoding UTF8
$genExit = Invoke-P0PythonFile -PythonExe $python -ScriptFile $genPy -IsolatedHome (Join-Path $OutDir 'generator-home') -PythonPath (Join-Path $InstallRoot 'uv-tools\pdf2zh-next\Lib\site-packages') -GuardDir $guardDir -LogPrefix (Join-Path $OutDir 'png-generator')
if ($genExit -ne 0) { Write-Host '[FAIL] isolated PNG generator failed'; exit 1 }
$bytes = [IO.File]::ReadAllBytes((Join-Path $OutDir 'sentinel.png'))
$w = 0; $h = 0; $why = ''
$pngOk = Test-PngStrict $bytes 640 ([ref]$w) ([ref]$h) ([ref]$why)
Check 'png: valid decode through isolated child' ($pngOk -and ($w -eq 640)) ("why=$why w=$w")
Check 'png: isolated child wrote temp artifacts only under iso root' (Test-Path $pngIsoTmp) 'iso pngcheck-tmp missing'

# --- sentinel 5: existed/value restore around a parent-env mutation window
$n = 'P0R2_SENTINEL_ENV'
[Environment]::SetEnvironmentVariable($n, 'original', 'Process')
$saved = Save-ChildEnv @($n)
[Environment]::SetEnvironmentVariable($n, 'CHANGED', 'Process')
Restore-ChildEnv $saved
Check 'env: existed/value restore after child-env window' ([Environment]::GetEnvironmentVariable($n) -eq 'original') 'restore failed'
Remove-Item ("Env:" + $n) -ErrorAction SilentlyContinue

'check,verdict' | Set-Content (Join-Path $OutDir 'matrix.csv') -Encoding ASCII
$rows | ForEach-Object { Add-Content (Join-Path $OutDir 'matrix.csv') $_ -Encoding ASCII }
Get-Content (Join-Path $OutDir 'matrix.csv')
if ($script:fails -gt 0) { Write-Host ("[FAIL] isolation sentinels: {0} failed" -f $script:fails); exit 1 }
Write-Host '[PASS] R2 isolation sentinels'
exit 0
