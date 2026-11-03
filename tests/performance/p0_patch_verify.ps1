# BabelDOC patch verification (ASCII only, PS 5.1 safe)
# Works ONLY on temp copies; never touches site-packages.
# Layout: temp root contains babeldoc/assets/assets.py; git apply uses the
# original relative diff header from the archived patch.
# Steps: 1) reverse-apply -> expect official wheel file SHA
#        2) forward-apply -> expect installed file SHA (round trip)
#        3) py_compile the replayed copy
# Evidence: docs/verification/native-desktop/patch-verify-<stamp>.txt

param(
    [string]$InstallRoot = 'D:\paper\pdf2zh-install-test',
    [string]$RepoRoot = 'D:\paper\PDFMathTranslate-next'
)

$ErrorActionPreference = 'Stop'
$python = Get-ChildItem (Join-Path $InstallRoot 'uv-python') -Recurse -Filter python.exe |
    Select-Object -First 1 -ExpandProperty FullName
$patch = Join-Path $RepoRoot 'build\patches\babeldoc\0001-assets-upstream-env.patch'
$installed = Join-Path $InstallRoot 'uv-tools\pdf2zh-next\Lib\site-packages\babeldoc\assets\assets.py'
if (-not (Test-Path $patch) -or -not (Test-Path $installed)) { Write-Host '[FAIL] input missing'; exit 4 }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$tempBase = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')
$root = Join-Path $tempBase ("pdf2zh-patchverify-" + $stamp + "-" + $PID)
$tree = Join-Path $root 'babeldoc\assets'
New-Item -ItemType Directory -Force -Path $tree | Out-Null
Set-Content -Path (Join-Path $root 'owner.json') -Value (@{ script='p0_patch_verify.ps1'; hostPid=$PID; created=(Get-Date).ToString('o'); root=$root } | ConvertTo-Json) -Encoding UTF8
Copy-Item $installed (Join-Path $tree 'assets.py') -Force

$log = Join-Path $RepoRoot ('docs\verification\native-desktop\patch-verify-' + $stamp + '.txt')
function Note($msg) { Write-Host $msg; $msg | Add-Content -Path $log -Encoding UTF8 }
Set-Content -Path $log -Value ("BabelDOC patch verification - " + (Get-Date -Format o)) -Encoding UTF8

$expectedOfficial = '208B394D48F6EC61AA6777BC384F0D9551CC2AED0A8DE8CBB28A45E770DBACD3'
$expectedInstalled = '3261EFFF6A27E9845E47A5127EE9FE76EF3A79C78C9F34A140A2ECE5D4C57F57'

$env:GIT_CONFIG_COUNT = '1'
$env:GIT_CONFIG_KEY_0 = 'safe.directory'
$env:GIT_CONFIG_VALUE_0 = '*'

Note ("installed SHA256: " + (Get-FileHash (Join-Path $tree 'assets.py') -Algorithm SHA256).Hash)
Note ("expected installed: " + $expectedInstalled)

# prepare clean patch (diff body only, original relative header, LF endings)
$lines = Get-Content $patch
$idx = ($lines | Select-String -Pattern '^diff --git' | Select-Object -First 1).LineNumber
$diffBody = $lines[($idx - 1)..($lines.Count - 1)]
$cleanPatch = Join-Path $root 'clean.patch'
# PS 5.1 Set-Content writes CRLF; git apply needs the original LF context
[IO.File]::WriteAllText($cleanPatch, (($diffBody -join "`n") + "`n"))
$numstat = git -c core.autocrlf=false -C $root apply --numstat clean.patch 2>&1
Note ("git apply --numstat: " + ($numstat -join ' | '))
if ($LASTEXITCODE -ne 0) { Note 'FAIL numstat'; exit 1 }

# step 1: reverse-apply -> official content
git -c core.autocrlf=false -C $root apply --reverse clean.patch 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Note ("FAIL reverse apply rc=" + $LASTEXITCODE); exit 1 }
$gotOfficial = (Get-FileHash (Join-Path $tree 'assets.py') -Algorithm SHA256).Hash
Note ("reverse-applied SHA256: " + $gotOfficial)
Note ("expected official : " + $expectedOfficial)
if ($gotOfficial -ne $expectedOfficial) { Note 'FAIL: mismatch vs official wheel file'; exit 1 }
Note 'PASS: reverse-applied content == official wheel babeldoc/assets/assets.py'

# step 2: forward-apply -> round trip back to installed content
git -c core.autocrlf=false -C $root apply clean.patch 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Note ("FAIL forward apply rc=" + $LASTEXITCODE); exit 1 }
$gotReplay = (Get-FileHash (Join-Path $tree 'assets.py') -Algorithm SHA256).Hash
Note ("forward-applied SHA256: " + $gotReplay)
if ($gotReplay -ne $expectedInstalled) { Note 'FAIL: replay mismatch vs installed file'; exit 1 }
Note 'PASS: forward replay == installed babeldoc/assets/assets.py'

# step 3: syntax check
& $python -m py_compile (Join-Path $tree 'assets.py') 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Note 'FAIL py_compile'; exit 1 }
Note 'PASS: py_compile on replayed file'

Note ("temp root preserved: " + $root)
Note 'RESULT: patch verified (reverse + forward + syntax) on temp copies only'
Write-Host ("evidence: {0}" -f $log)
exit 0
