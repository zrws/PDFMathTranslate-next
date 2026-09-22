# Build the full Windows distribution of PDFMathTranslate:
#   1) publish the WebView2 launcher (self-contained single-file exe)
#   2) assemble the release payload (portable Python runtime + launcher + version.json)
#   3) compile the Inno Setup installer
#   4) emit latest.json for the in-app auto-updater
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File build\build-release.ps1 [-Version 2.9.0] [-SkipInstaller]
# Requires: .NET 8 SDK (or ..\.dotnet-sdk\dotnet.exe), Inno Setup 6 (unless -SkipInstaller)

param(
    [string]$Version = "",
    [switch]$SkipInstaller
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path   # ...\build
$ProjectRoot = Split-Path -Parent $ScriptDir                   # repo root
$Dist = Join-Path $ProjectRoot 'dist'
$Payload = Join-Path $Dist 'payload'
$LauncherPublish = Join-Path $ProjectRoot 'launcher\publish'

# ---------------------------------------------------------------------------
# toolchain resolution
# ---------------------------------------------------------------------------
function Resolve-Dotnet {
    $localSdk = Join-Path (Split-Path -Parent $ProjectRoot) '.dotnet-sdk\dotnet.exe'
    if (Test-Path $localSdk) { return $localSdk }
    $cmd = Get-Command dotnet -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw 'dotnet SDK not found. Install .NET 8 SDK or place dotnet.exe at ..\.dotnet-sdk\dotnet.exe'
}

function Resolve-ISCC {
    $candidates = @(
        "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
        "C:\Program Files\Inno Setup 6\ISCC.exe",
        (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe')
    )
    foreach ($p in $candidates) { if (Test-Path $p) { return $p } }
    $cmd = Get-Command ISCC -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

# ---------------------------------------------------------------------------
# version detection (source\pdf2zh_next\__init__.py -> __version__)
# ---------------------------------------------------------------------------
if (-not $Version) {
    $initPy = Join-Path $ProjectRoot 'source\pdf2zh_next\__init__.py'
    $match = Select-String -Path $initPy -Pattern '__version__\s*=\s*"([^"]+)"' | Select-Object -First 1
    if (-not $match) { throw 'Cannot detect version from source\pdf2zh_next\__init__.py' }
    $Version = $match.Matches[0].Groups[1].Value
}
Write-Host "Version: $Version"

# ---------------------------------------------------------------------------
# clean output dirs
# ---------------------------------------------------------------------------
if (Test-Path $Dist) { Remove-Item $Dist -Recurse -Force }
New-Item -ItemType Directory -Force -Path $Payload | Out-Null

# ---------------------------------------------------------------------------
# 1) publish launcher
# ---------------------------------------------------------------------------
$dotnet = Resolve-Dotnet
Write-Host 'Publishing WebView2 launcher...'
& $dotnet publish (Join-Path $ProjectRoot 'launcher\PDFMathTranslateLauncher.csproj') `
    --configuration Release --runtime win-x64 --self-contained true `
    --output $LauncherPublish
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed ($LASTEXITCODE)" }
$exe = Join-Path $LauncherPublish 'PDFMathTranslate.exe'
if (-not (Test-Path $exe)) { throw 'Launcher publish output missing PDFMathTranslate.exe' }

# ---------------------------------------------------------------------------
# 2) assemble release payload (portable runtime, no user data)
#    user data lives in home\ (created at runtime) and is never shipped here
# ---------------------------------------------------------------------------
Write-Host 'Assembling release payload...'
Copy-Item $exe $Payload
Copy-Item (Join-Path $ProjectRoot 'start-gui-direct.py') $Payload
Copy-Item (Join-Path $ProjectRoot 'start-webui.py') $Payload
robocopy (Join-Path $ProjectRoot 'webui') (Join-Path $Payload 'webui') /MIR /NFL /NDL /NJH /NJS /NP /XD design-export | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy webui failed ($LASTEXITCODE)" }
Get-ChildItem -Path $ProjectRoot -Filter '*.md' -File | Where-Object { $_.Name -ne 'CODELY.md' } | ForEach-Object { Copy-Item $_.FullName $Payload }
if (Test-Path (Join-Path $ProjectRoot 'bin')) {
    Copy-Item (Join-Path $ProjectRoot 'bin') (Join-Path $Payload 'bin') -Recurse
}
robocopy (Join-Path $ProjectRoot 'uv-python') (Join-Path $Payload 'uv-python') /MIR /NFL /NDL /NJH /NJS /NP /XF *.pyc /XD __pycache__ | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy uv-python failed ($LASTEXITCODE)" }
robocopy (Join-Path $ProjectRoot 'uv-tools') (Join-Path $Payload 'uv-tools') /MIR /NFL /NDL /NJH /NJS /NP /XF *.pyc /XD __pycache__ .pytest_cache | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy uv-tools failed ($LASTEXITCODE)" }
@{ version = $Version } | ConvertTo-Json | Set-Content (Join-Path $Payload 'version.json') -Encoding ascii
# also drop version.json into the repo root so the portable/dev copy can self-update-check
@{ version = $Version } | ConvertTo-Json | Set-Content (Join-Path $ProjectRoot 'version.json') -Encoding ascii

# ---------------------------------------------------------------------------
# 3) compile installer
# ---------------------------------------------------------------------------
$setupPath = $null
if (-not $SkipInstaller) {
    $iscc = Resolve-ISCC
    if ($iscc) {
        Write-Host 'Compiling installer with Inno Setup...'
        & $iscc "/DAppVersion=$Version" "/DPayloadRoot=$Payload" (Join-Path $ScriptDir 'installer.iss')
        if ($LASTEXITCODE -ne 0) { throw "ISCC failed ($LASTEXITCODE)" }
        $setupPath = Join-Path $Dist "PDFMathTranslate-Setup-$Version.exe"
        if (-not (Test-Path $setupPath)) { throw 'Installer missing after ISCC run' }
    }
    else {
        Write-Warning 'Inno Setup 6 not found - installer skipped. Install it with: winget install JRSoftware.InnoSetup'
    }
}

# ---------------------------------------------------------------------------
# 4) latest.json (auto-update manifest, upload next to the installer)
# ---------------------------------------------------------------------------
if ($setupPath) {
    Write-Host 'Generating latest.json...'
    $sha256 = (Get-FileHash $setupPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $size = (Get-Item $setupPath).Length
    [ordered]@{
        version = $Version
        url     = "https://github.com/zrws/PDFMathTranslate-next/releases/download/v$Version/PDFMathTranslate-Setup-$Version.exe"
        sha256  = $sha256
        notes   = "PDFMathTranslate $Version"
        size    = $size
    } | ConvertTo-Json | Set-Content (Join-Path $Dist 'latest.json') -Encoding ascii
}

Write-Host ''
Write-Host 'Build finished.'
if ($setupPath) {
    Write-Host "  Installer : $setupPath"
    Write-Host "  Manifest  : $(Join-Path $Dist 'latest.json')"
    Write-Host ''
    Write-Host 'Publish to GitHub Releases:'
    Write-Host "  gh release create v$Version dist\PDFMathTranslate-Setup-$Version.exe dist\latest.json --title v$Version --generate-notes"
}
else {
    Write-Host "  Payload   : $Payload"
}
