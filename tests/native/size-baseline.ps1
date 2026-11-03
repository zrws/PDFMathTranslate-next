param([Parameter(Mandatory=$true)][string]$ReferenceRepo,[Parameter(Mandatory=$true)][string]$RuntimeRoot,[Parameter(Mandatory=$true)][string]$LegacyExe,[Parameter(Mandatory=$true)][string]$IsccExe,[Parameter(Mandatory=$true)][string]$EvidenceRoot)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if(Test-Path -LiteralPath $EvidenceRoot){throw '证据目录必须全新'}
$id=[guid]::NewGuid().ToString('N').Substring(0,12)
$payload=Join-Path $repo ('.local/size-baseline-'+$id)
New-Item -ItemType Directory -Path $payload,$EvidenceRoot|Out-Null
function Copy-Tree([string]$From,[string]$To,[string[]]$Exclude=@()){
    & robocopy $From $To /E /MT:4 /R:2 /W:1 /NFL /NDL /NJH /NJS /NP /XF *.pyc *.map /XD __pycache__ .pytest_cache tests test @Exclude
    if($LASTEXITCODE -lt 0 -or $LASTEXITCODE -ge 8){throw 'baseline copy failed'}
}
$packages=Join-Path $RuntimeRoot 'uv-tools/pdf2zh-next/Lib/site-packages'
$exclude=@(Get-ChildItem -LiteralPath $packages -Directory|Where-Object {$_.Name -in @('gradio','gradio_client','gradio_pdf','pdf2zh_next') -or $_.Name -match '^gradio(-|_client-|_pdf-).*\.dist-info$'}|ForEach-Object FullName)
Copy-Tree (Join-Path $RuntimeRoot 'uv-python') (Join-Path $payload 'uv-python') @('include')
Copy-Tree (Join-Path $RuntimeRoot 'uv-tools/pdf2zh-next') (Join-Path $payload 'uv-tools/pdf2zh-next') $exclude
Copy-Tree (Join-Path $ReferenceRepo 'source/pdf2zh_next') (Join-Path $payload 'uv-tools/pdf2zh-next/Lib/site-packages/pdf2zh_next')
Copy-Tree (Join-Path $ReferenceRepo 'webui') (Join-Path $payload 'webui') @('design-export')
Copy-Item -LiteralPath $LegacyExe -Destination (Join-Path $payload 'PDFMathTranslate.exe')
Copy-Item -LiteralPath (Join-Path $ReferenceRepo 'start-webui.py') -Destination $payload
Get-ChildItem -LiteralPath $ReferenceRepo -File -Filter *.md|Where-Object Name -notin @('CODELY.md','REPAIR_PLAN_2026-09-22.md')|Copy-Item -Destination $payload
if(Test-Path -LiteralPath (Join-Path $ReferenceRepo 'bin')){Copy-Tree (Join-Path $ReferenceRepo 'bin') (Join-Path $payload 'bin')}
'{"version":"2.9.0"}'|Set-Content (Join-Path $payload 'version.json') -Encoding ascii
$rows=Get-ChildItem -LiteralPath $payload -Recurse -File|Sort-Object FullName|ForEach-Object {$_.FullName.Substring($payload.Length+1)+'|'+(Get-FileHash -LiteralPath $_.FullName).Hash}
[IO.File]::WriteAllLines((Join-Path $payload 'owned-files.tsv'),[string[]]$rows,[Text.UTF8Encoding]::new($true))
& $IsccExe '/DAppVersion=2.9.0' "/DPayloadRoot=$payload" "/DInstallerOutputDir=$EvidenceRoot" (Join-Path $repo 'build/installer.iss') *> (Join-Path $EvidenceRoot 'compile.log')
if($LASTEXITCODE){throw 'baseline compression failed'}
$installer=Join-Path $EvidenceRoot 'PDFMathTranslate-Setup-2.9.0.exe'
@{scope='controlled size-only reference, not a historical release reproduction; old self-contained WinForms/WebView2 launcher and source, same locked local Python dependencies, same Inno compression; never installed or launched';reference_commit=(& git -C $ReferenceRepo rev-parse HEAD);reference_repo=$ReferenceRepo;runtime=$RuntimeRoot;legacy_exe=$LegacyExe;legacy_sha256=(Get-FileHash -LiteralPath $LegacyExe).Hash;payload=$payload;payload_bytes=(Get-ChildItem -LiteralPath $payload -File -Recurse|Measure-Object Length -Sum).Sum;payload_files=@(Get-ChildItem -LiteralPath $payload -File -Recurse).Count;installer_bytes=(Get-Item -LiteralPath $installer).Length;installer_sha256=(Get-FileHash -LiteralPath $installer).Hash;compression='lzma2/normal; SolidCompression=no';excluded='Gradio same as old slim build; tests/test/__pycache__; no user data/models/font cache'}|ConvertTo-Json -Depth 4|Set-Content (Join-Path $EvidenceRoot 'report.json') -Encoding utf8
# The binary stays in ignored dist, not Git evidence.
