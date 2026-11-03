# Isolated startup gate regression, including swallowed sitecustomize errors.
param([string]$PythonExe = '', [string]$EvidenceRoot = '', [string]$RepoRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent))
. (Join-Path $PSScriptRoot 'p0_paths.ps1')
$ErrorActionPreference = 'Stop'
$EvidenceRoot = Resolve-P0EvidenceRoot $RepoRoot $EvidenceRoot
$outDir = Join-Path $EvidenceRoot ('runs/python-child-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$python = Resolve-P0Python (Join-Path $RepoRoot '.local/runtime') $PythonExe
$payload = Join-Path $outDir 'payload.py'
@'
import json, os, sys
from pathlib import Path
Path(sys.argv[1]).write_text(json.dumps({"argv":sys.argv[2:], "home":os.environ["HOME"], "cwd":os.getcwd(), "proxy":os.environ.get("HTTPS_PROXY"), "no_user_site":os.environ.get("PYTHONNOUSERSITE")}), encoding="utf-8")
'@ | Set-Content $payload -Encoding UTF8
$result = Join-Path $outDir 'result.json'
$guard = Join-Path $PSScriptRoot 'p0_guard'
$rc = Invoke-P0PythonFile -PythonExe $python -ScriptFile $payload -ScriptArgs @($result,'path with space','中文参数') -IsolatedHome (Join-Path $outDir 'home') -GuardDir $guard -LogPrefix (Join-Path $outDir 'valid')
$info = Get-Content $result -Raw -Encoding UTF8 | ConvertFrom-Json
$checks = @(@{ check='unicode-args-startup-isolation'; passed=($rc -eq 0 -and $info.argv[0] -eq 'path with space' -and $info.argv[1] -eq '中文参数' -and -not $info.proxy -and $info.no_user_site -eq '1' -and $info.home -like ($outDir + '*') -and $info.cwd -like ($outDir + '*')) })
$bad = Join-Path $outDir 'corrupt-guard'
New-Item -ItemType Directory -Path $bad | Out-Null
Copy-Item (Join-Path $guard 'entry_wrapper.py'),(Join-Path $guard 'entry_gate.py') $bad
"raise RuntimeError('controlled sitecustomize failure')" | Set-Content (Join-Path $bad 'sitecustomize.py') -Encoding ASCII
$never = Join-Path $outDir 'must-not-exist.json'
$badRc = Invoke-P0PythonFile -PythonExe $python -ScriptFile $payload -ScriptArgs @($never) -IsolatedHome (Join-Path $outDir 'bad-home') -GuardDir $bad -LogPrefix (Join-Path $outDir 'bad')
$checks += @{ check='swallowed-guard-import-error-rejected-before-payload'; passed=($badRc -eq 1 -and -not (Test-Path $never) -and (Get-Content (Join-Path $outDir 'bad.stderr.txt') -Raw) -match 'ENTRY_GATE') }
$checks | ConvertTo-Json | Set-Content (Join-Path $outDir 'checks.json') -Encoding UTF8
$hashes=@{}
foreach ($file in @('p0_paths.ps1','p0_python_child_negtest.ps1','p0_guard/entry_wrapper.py','p0_guard/entry_gate.py','p0_guard/sitecustomize.py')) { $hashes[$file]=(Get-FileHash (Join-Path $PSScriptRoot $file) -Algorithm SHA256).Hash }
$hashes|ConvertTo-Json|Set-Content (Join-Path $outDir 'script-hashes.json') -Encoding UTF8
$checks | ForEach-Object {[pscustomobject]$_} | Format-Table
if (@($checks|Where-Object {-not $_.passed}).Count) {exit 1}
exit 0
