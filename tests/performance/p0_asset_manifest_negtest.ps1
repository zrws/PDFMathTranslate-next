# M5: synthetic manifests; real isolated Python hash subprocess. No packages/models.
param(
    [string]$RepoRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent),
    [string]$InstallRoot = '',
    [string]$PythonExe = '',
    [string]$EvidenceRoot = '',
    [string]$OutDir = ''
)
. (Join-Path $PSScriptRoot 'p0_paths.ps1')
$ErrorActionPreference = 'Stop'
$EvidenceRoot = Resolve-P0EvidenceRoot $RepoRoot $EvidenceRoot
if (-not $OutDir) { $OutDir = Join-Path $EvidenceRoot ('runs\asset-manifest-' + [guid]::NewGuid().ToString('N')) }
if (Test-Path -LiteralPath $OutDir) { Write-Host '[FAIL] output exists (refuse overwrite)'; exit 2 }
New-Item -ItemType Directory -Path $OutDir | Out-Null
$python = Resolve-P0Python $InstallRoot $PythonExe
$fixture = Join-Path $OutDir 'fixture'
$cache = Join-Path $fixture 'cache'
$install = Join-Path $fixture 'install'
New-Item -ItemType Directory -Force -Path (Join-Path $install 'uv-tools\pdf2zh-next\Lib\site-packages'), (Join-Path $cache 'models') | Out-Null
[IO.File]::WriteAllBytes((Join-Path $cache 'models\stub.bin'), [byte[]](97,98,99))
# SHA3-256('abc'), a standard test vector; never requires a downloaded asset.
$validHash = '3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532'
$worker = Join-Path $OutDir 'worker.ps1'
@'
param($Helper, $Cache, $Install, $Iso, $Python, $Meta, $Case, $Result)
$ErrorActionPreference = 'Stop'
. $Helper
try {
    $ok = Invoke-AssetCheck -CacheDir $Cache -InstallRoot $Install -IsolatedHome $Iso -PythonExe $Python -TestMetaJsonPath $Meta -TestHashToolFailure:($Case -eq 'hash_tool_failed')
    @{ case = $Case; ok = [bool]$ok; status = 'verified'; pid = $PID } | ConvertTo-Json | Set-Content $Result -Encoding UTF8
    if ($ok) { exit 0 } else { exit 4 }
} catch {
    @{ case = $Case; ok = $false; status = 'unverified'; error = $_.Exception.Message; pid = $PID } | ConvertTo-Json | Set-Content $Result -Encoding UTF8
    exit 5
}
'@ | Set-Content $worker -Encoding ASCII
$rows = @()
foreach ($case in @('valid','metadata_unparseable','empty_manifest','missing_category','hash_tool_failed','asset_missing','asset_corrupt')) {
    $dir = Join-Path $OutDir $case
    $iso = Join-Path $dir 'isolated-home'
    New-Item -ItemType Directory -Force -Path $iso | Out-Null
    $items = [ordered]@{ fonts = @(); models = @(@{ name = 'stub.bin'; sha3_256 = $validHash }); cmap = @(); tiktoken = @() }
    if ($case -eq 'empty_manifest') { $items.models = @() }
    if ($case -eq 'missing_category') { $items.Remove('fonts') }
    if ($case -eq 'asset_missing') { $items.models[0].name = 'missing.bin' }
    if ($case -eq 'asset_corrupt') { $items.models[0].sha3_256 = '0' * 64 }
    $meta = Join-Path $dir 'metadata.json'
    if ($case -eq 'metadata_unparseable') { '{broken' | Set-Content $meta -Encoding ASCII }
    else { @{ file_list = $items; effective_home = $iso; cache_folder = $cache; babeldoc_version = 'synthetic-not-installed' } | ConvertTo-Json -Depth 6 | Set-Content $meta -Encoding UTF8 }
    $stdout = Join-Path $dir 'stdout.txt'; $stderr = Join-Path $dir 'stderr.txt'
    $result = Join-Path $dir 'result.json'
    $argv = @('-NoProfile','-File',$worker,'-Helper',(Join-Path $PSScriptRoot 'p0_asset_check.ps1'),'-Cache',$cache,'-Install',$install,'-Iso',$iso,'-Python',$python,'-Meta',$meta,'-Case',$case,'-Result',$result)
    $started = (Get-Date).ToString('o')
    $p = Start-P0PowerShell -ArgumentList (($argv | ForEach-Object { ConvertTo-P0Argument $_ }) -join ' ') -PassThru -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $childPid = $p.Id
    $p.WaitForExit()
    $p.Refresh()
    $expected = if ($case -eq 'valid') { 0 } else { 4 }
    $text = Get-Content $stdout -Raw
    $reasonOk = if ($case -eq 'valid') { $text -match 'total=1 verified=1.*PASS' } else { $text -match ([regex]::Escape($case)) }
    $verified = (Test-Path $result) -and ((Get-Content $result -Raw | ConvertFrom-Json).status -eq 'verified')
    $rows += [pscustomobject]@{ case = $case; expected_exit = $expected; observed_exit = $p.ExitCode; expected_reason = $case; reason_matched = [bool]$reasonOk; status = $(if ($verified) { 'verified' } else { 'unverified' }); verdict = $(if ($verified -and $p.ExitCode -eq $expected -and $reasonOk) { 'PASS' } else { 'FAIL' }); pid = $childPid; started = $started; ended = (Get-Date).ToString('o'); arguments = $argv; cleanup = 'child exited; fixtures preserved' }
}
$rows | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $OutDir 'cases.json') -Encoding UTF8
$rows | Select-Object case,expected_exit,observed_exit,reason_matched,status,verdict | Export-Csv (Join-Path $OutDir 'matrix.csv') -NoTypeInformation -Encoding UTF8
$hashes = @{}
foreach ($f in @('p0_asset_check.ps1','p0_asset_manifest_negtest.ps1','p0_paths.ps1')) { $hashes[$f] = (Get-FileHash (Join-Path $PSScriptRoot $f) -Algorithm SHA256).Hash }
$hashes | ConvertTo-Json | Set-Content (Join-Path $OutDir 'script-hashes.json') -Encoding UTF8
$rows | Format-Table case,observed_exit,reason_matched,status,verdict
if (@($rows | Where-Object { $_.verdict -ne 'PASS' }).Count) { exit 1 }
exit 0
