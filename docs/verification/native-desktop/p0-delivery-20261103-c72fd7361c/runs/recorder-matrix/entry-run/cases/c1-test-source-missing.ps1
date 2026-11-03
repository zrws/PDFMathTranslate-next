param([string]$RepoRoot, [string]$InstallRoot, [string]$EvidenceRoot, [string]$PythonExe)
$src = Join-Path $env:TEMP ("pdf2zh-c1-test-" + [guid]::NewGuid().ToString('N').Substring(0,8))
$repo = $RepoRoot
$install = $InstallRoot
$iso = Join-Path $src 'iso-home'
New-Item -ItemType Directory -Force -Path $src, "$iso\.config\pdf2zh" | Out-Null
. (Join-Path $repo 'tests\performance\p0_asset_check.ps1')
$ok = Invoke-AssetCheck -CacheDir $src -InstallRoot $install -IsolatedHome $iso -PythonExe $PythonExe
if ($ok) { Write-Host 'UNEXPECTED PASS'; exit 1 } else { Write-Host 'EXPECTED FAIL asset_missing'; exit 4 }
