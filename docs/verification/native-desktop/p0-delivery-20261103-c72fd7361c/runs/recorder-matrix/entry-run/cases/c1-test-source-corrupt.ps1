param([string]$RepoRoot, [string]$InstallRoot, [string]$EvidenceRoot, [string]$PythonExe)
$src = Join-Path $env:TEMP ("pdf2zh-c1-test-" + [guid]::NewGuid().ToString('N').Substring(0,8))
$repo = $RepoRoot
$install = $InstallRoot
$iso = Join-Path $src 'iso-home'
New-Item -ItemType Directory -Force -Path "$src\models", "$iso\.config\pdf2zh" | Out-Null
$realModel = Get-ChildItem (Join-Path $install 'home\.cache\babeldoc\models') -File | Select-Object -First 1
Copy-Item $realModel.FullName "$src\models\$($realModel.Name)"
$bytes = [IO.File]::ReadAllBytes("$src\models\$($realModel.Name)")
$bytes[0] = 0x00; $bytes[1] = 0x01; $bytes[2] = 0x02
[IO.File]::WriteAllBytes("$src\models\$($realModel.Name)", $bytes)
. (Join-Path $repo 'tests\performance\p0_asset_check.ps1')
$ok = Invoke-AssetCheck -CacheDir $src -InstallRoot $install -IsolatedHome $iso -PythonExe $PythonExe
if ($ok) { Write-Host 'UNEXPECTED PASS'; exit 1 } else { Write-Host 'EXPECTED FAIL asset_corrupt'; exit 4 }
