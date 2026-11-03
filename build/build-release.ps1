# Build the full Windows distribution of PDFMathTranslate:
#   1) publish the WebView2 launcher (self-contained single-file exe)
#   2) assemble a slim release payload (single Python runtime + launcher + version.json)
#   3) compile the Inno Setup installer
#   4) emit latest.json for the in-app auto-updater
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File build\build-release.ps1 [-Version 2.9.0] [-SkipInstaller] [-IncludeLegacyGui]
# Requires: .NET 8 SDK (or ..\.dotnet-sdk\dotnet.exe), Inno Setup 6 (unless -SkipInstaller)

param(
    [string]$Version = "",
    [switch]$SkipInstaller,
    [switch]$CleanDist,
    [switch]$IncludeLegacyGui,
    [switch]$LegacyWebView,
    [string]$DotnetExe,
    [string]$UvExe,
    [string]$PythonRoot,
    [string]$IsccExe,
    [string]$LegacyRuntimeRoot,
    [switch]$Offline,
    [ValidateSet('preview','stable')][string]$Channel='preview'
)

$ErrorActionPreference = 'Stop'
if (!$LegacyWebView) {
    $native=@{DotnetExe=$DotnetExe;UvExe=$UvExe;PythonRoot=$PythonRoot;IsccExe=$IsccExe;SkipInstaller=$SkipInstaller;Offline=$Offline;Channel=$Channel}
    if($Version){$native.Version=$Version}
    & (Join-Path $PSScriptRoot 'build-native.ps1') @native
    exit $LASTEXITCODE
}
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path   # ...\build
$ProjectRoot = Split-Path -Parent $ScriptDir                   # repo root
$Dist = Join-Path $ProjectRoot 'dist'
$Payload = Join-Path $Dist ("payload-build-" + $PID)
$LauncherPublish = Join-Path $ProjectRoot 'launcher\publish'
$SourcePackage = Join-Path $ProjectRoot 'source\pdf2zh_next'
$LegacyRuntimeRoot = if($LegacyRuntimeRoot){(Resolve-Path -LiteralPath $LegacyRuntimeRoot).Path}else{$ProjectRoot}
$RuntimeRoot = Join-Path $LegacyRuntimeRoot 'uv-tools\pdf2zh-next'
$UvPythonRoot = Join-Path $LegacyRuntimeRoot 'uv-python'
$PayloadRuntimePackage = Join-Path $Payload 'uv-tools\pdf2zh-next\Lib\site-packages\pdf2zh_next'

# ---------------------------------------------------------------------------
# toolchain resolution
# ---------------------------------------------------------------------------
function Resolve-Dotnet {
    if($DotnetExe){return (Resolve-Path -LiteralPath $DotnetExe).Path}
    $localSdk = Join-Path (Split-Path -Parent $ProjectRoot) '.dotnet-sdk\dotnet.exe'
    if (Test-Path $localSdk) { return $localSdk }
    $cmd = Get-Command dotnet -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw 'dotnet SDK not found. Install .NET 8 SDK or place dotnet.exe at ..\.dotnet-sdk\dotnet.exe'
}

function Resolve-ISCC {
    if($IsccExe){return (Resolve-Path -LiteralPath $IsccExe).Path}
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
# prepare output dirs. Each run uses an isolated payload directory so Windows
# file scanners or a previous compiler process cannot block a consecutive build.
# ---------------------------------------------------------------------------
if ($CleanDist) { throw '本构建保留已有 dist；请使用每轮独立输出，不自动递归清理。' }
if (-not (Test-Path $Dist)) { New-Item -ItemType Directory -Force -Path $Dist | Out-Null }
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
if (-not (Test-Path -LiteralPath $RuntimeRoot)) {
    throw "Packaged Python runtime not found: $RuntimeRoot"
}
Copy-Item $exe $Payload
Copy-Item (Join-Path $ProjectRoot 'start-webui.py') $Payload
if ($IncludeLegacyGui) {
    Copy-Item (Join-Path $ProjectRoot 'start-gui-direct.py') $Payload
}
robocopy (Join-Path $ProjectRoot 'webui') (Join-Path $Payload 'webui') /MIR /NFL /NDL /NJH /NJS /NP /XD design-export | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy webui failed ($LASTEXITCODE)" }
Get-ChildItem -Path $ProjectRoot -Filter '*.md' -File | Where-Object { $_.Name -notin @('CODELY.md', 'REPAIR_PLAN_2026-09-22.md') } | ForEach-Object { Copy-Item $_.FullName $Payload }
if (Test-Path (Join-Path $ProjectRoot 'bin')) {
    Copy-Item (Join-Path $ProjectRoot 'bin') (Join-Path $Payload 'bin') -Recurse
}
# The repository can contain both a versioned CPython directory and a byte-for-byte
# compatibility alias. Package only the interpreter referenced by the venv.
$pyvenvConfig = Join-Path $RuntimeRoot 'pyvenv.cfg'
$runtimeName = $null
if (Test-Path $pyvenvConfig) {
    $homeLine = Get-Content $pyvenvConfig | Where-Object { $_ -match '^home\s*=' } | Select-Object -First 1
    if ($homeLine -and $homeLine -match '^home\s*=\s*(.+)$') {
        $runtimeName = Split-Path -Leaf $Matches[1].Trim()
    }
}
$pythonRuntime = if($PythonRoot){(Resolve-Path -LiteralPath $PythonRoot).Path}elseif ($runtimeName) { Join-Path $UvPythonRoot $runtimeName } else { $null }
if (-not $pythonRuntime -or -not (Test-Path -LiteralPath $pythonRuntime)) {
    $pythonRuntime = Get-ChildItem -LiteralPath $UvPythonRoot -Directory |
        Where-Object { $_.Name -match '^cpython-\d+\.\d+\.\d+-windows-x86_64-none$' } |
        Sort-Object Name -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}
if (-not $pythonRuntime) { throw "Versioned portable Python runtime not found: $UvPythonRoot" }
$payloadPython = Join-Path (Join-Path $Payload 'uv-python') (Split-Path -Leaf $pythonRuntime)
robocopy $pythonRuntime $payloadPython /MIR /NFL /NDL /NJH /NJS /NP `
    /XF *.pyc *.map `
    /XD __pycache__ .pytest_cache tests test include | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy uv-python failed ($LASTEXITCODE)" }

# The installed app uses the FastAPI/WebView2 interface. Gradio remains available
# in source builds and can be restored in the installer with -IncludeLegacyGui.
$runtimeExcludeDirs = @('__pycache__', '.pytest_cache', 'tests', 'test')
if (-not $IncludeLegacyGui) {
    $sitePackages = Join-Path $RuntimeRoot 'Lib\site-packages'
    $legacyGuiDirs = Get-ChildItem -LiteralPath $sitePackages -Directory | Where-Object {
        $_.Name -in @('gradio', 'gradio_client', 'gradio_pdf') -or
        $_.Name -match '^gradio-[0-9].*\.dist-info$' -or
        $_.Name -match '^gradio_(client|pdf)-.*\.dist-info$'
    }
    $runtimeExcludeDirs += $legacyGuiDirs.FullName
}
$runtimeCopyArgs = @(
    $RuntimeRoot,
    (Join-Path $Payload 'uv-tools\pdf2zh-next'),
    '/MIR', '/NFL', '/NDL', '/NJH', '/NJS', '/NP',
    '/XF', '*.pyc', '*.map',
    '/XD'
) + $runtimeExcludeDirs
& robocopy @runtimeCopyArgs | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy uv-tools failed ($LASTEXITCODE)" }
Write-Host 'Overlaying current source package into the release payload...'
robocopy $SourcePackage $PayloadRuntimePackage /MIR /NFL /NDL /NJH /NJS /NP /XF *.pyc /XD __pycache__ .pytest_cache | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy source package failed ($LASTEXITCODE)" }
@{ version = $Version; channel = $Channel } | ConvertTo-Json | Set-Content (Join-Path $Payload 'version.json') -Encoding ascii
# also drop version.json into the repo root so the portable/dev copy can self-update-check
@{ version = $Version; channel = $Channel } | ConvertTo-Json | Set-Content (Join-Path $ProjectRoot 'version.json') -Encoding ascii
$owned=Get-ChildItem -LiteralPath $Payload -File -Recurse | Sort-Object FullName | ForEach-Object {$_.FullName.Substring($Payload.Length+1)+'|'+(Get-FileHash -LiteralPath $_.FullName).Hash}
[IO.File]::WriteAllLines((Join-Path $Payload 'owned-files.tsv'),[string[]]$owned,[Text.UTF8Encoding]::new($true))

# ---------------------------------------------------------------------------
# 3) compile installer
# ---------------------------------------------------------------------------
$setupPath = $null
if (-not $SkipInstaller) {
    $iscc = Resolve-ISCC
    if ($iscc) {
        Write-Host 'Compiling installer with Inno Setup...'
        & $iscc "/DAppVersion=$Version" "/DPayloadRoot=$Payload" "/DInstallerOutputDir=$Dist" (Join-Path $ScriptDir 'installer.iss')
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
if ($setupPath -and $Channel -eq 'stable') {
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

    # Retain this owned payload and build evidence for review.
}

Write-Host ''
Write-Host 'Build finished.'
if ($setupPath) {
    Write-Host "  Installer : $setupPath"
    Write-Host "  Manifest  : $(Join-Path $Dist 'latest.json')"
    Write-Host ''
    Write-Host 'Local build only; no tag, Release or online latest.json was changed.'
}
else {
    Write-Host "  Payload   : $Payload"
}
