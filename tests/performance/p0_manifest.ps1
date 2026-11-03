# Identity manifest generator v3 (ASCII only, PS 5.1 safe)
# F4: parent PYTHONPATH/Git env saved and restored in finally.
# F6: -SampleDir hashes actual sample files in place (supplementary seal).
# Captures: repo identity, code hashes (repo vs installed), interpreter,
# dependency versions, machine/power context, script/sample hashes.

param(
    [string]$PythonExe = '',
    [string]$InstallRoot = (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) '.local\runtime'),
    [string]$RepoRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent),
    [string]$RunDir = '',
    [string]$SampleDir = ''
)

. (Join-Path $PSScriptRoot 'p0_paths.ps1')

$ErrorActionPreference = 'Stop'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
if (-not $RunDir) { $RunDir = Join-Path $RepoRoot "docs\verification\native-desktop\run-v3-$stamp" }
New-Item -ItemType Directory -Force -Path $RunDir | Out-Null

$savedPy = $env:PYTHONPATH
$savedGc = @($env:GIT_CONFIG_COUNT, $env:GIT_CONFIG_KEY_0, $env:GIT_CONFIG_VALUE_0)
try {
    $env:GIT_CONFIG_COUNT = '1'
    $env:GIT_CONFIG_KEY_0 = 'safe.directory'
    $env:GIT_CONFIG_VALUE_0 = ($RepoRoot -replace '\\','/')

    $repoFiles = @(
        'source/pdf2zh_next/__init__.py',
        'source/pdf2zh_next/const.py',
        'source/pdf2zh_next/http_api.py',
        'source/pdf2zh_next/high_level.py',
        'source/pdf2zh_next/config/model.py',
        'source/pdf2zh_next/translator/utils.py',
        'source/pdf2zh_next/translator/cache.py',
        'start-webui.py'
    )
    $sp = Join-Path $InstallRoot 'uv-tools\pdf2zh-next\Lib\site-packages'
    $installedFiles = @(
        'pdf2zh_next/__init__.py',
        'pdf2zh_next/const.py',
        'pdf2zh_next/http_api.py',
        'pdf2zh_next/high_level.py',
        'pdf2zh_next/config/model.py',
        'pdf2zh_next/translator/utils.py',
        'pdf2zh_next/translator/cache.py'
    )

    function Sha([string]$p) { if (Test-Path $p) { return (Get-FileHash $p -Algorithm SHA256).Hash } return $null }

    $repoHashes = [ordered]@{}
    foreach ($f in $repoFiles) { $repoHashes[$f] = Sha (Join-Path $RepoRoot $f) }
    $instHashes = [ordered]@{}
    foreach ($f in $installedFiles) { $instHashes[$f] = Sha (Join-Path $sp $f) }

    $python = Resolve-P0Python $InstallRoot $PythonExe
    $pyVer = & $python -c "import sys; print(sys.version)" 2>$null

    $pkgCode = @'
from importlib import metadata
for name in ["babeldoc", "pymupdf", "onnxruntime", "numpy", "opencv-python-headless",
             "scipy", "scikit-learn", "scikit-image", "fastapi", "uvicorn", "pydantic",
             "pdf2zh-next", "requests", "openai"]:
    try:
        print(f"{name}=={metadata.version(name)}")
    except Exception:
        print(f"{name}==<not installed>")
'@
    $pkgFile = Join-Path $RunDir 'pkg_versions.py'
    Set-Content -Path $pkgFile -Value $pkgCode -Encoding ASCII
    $env:PYTHONPATH = $sp
    $pkgVersions = & $python $pkgFile 2>&1
    if ($null -ne $savedPy) { $env:PYTHONPATH = $savedPy } else { Remove-Item Env:PYTHONPATH -ErrorAction SilentlyContinue }

    $lockLine = Select-String -Path (Join-Path $RepoRoot 'source\uv.lock') -Pattern 'name = "babeldoc"' -Context 0,4 -ErrorAction SilentlyContinue
    $lockEntry = if ($lockLine) { ($lockLine.Context.PostContext -join ' | ') } else { '<entry not found>' }

    $cpu = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name
    $ramGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
    $power = (powercfg /getactivescheme) -join ' '

    $dirty = git -C $RepoRoot status -u --porcelain=v1

    $samples = [ordered]@{}
    if ($SampleDir -and (Test-Path $SampleDir)) {
        foreach ($s in @('p0-sample-20p.pdf', 'p0-sample-1p.pdf')) {
            $p = Join-Path $SampleDir $s
            if (Test-Path $p) { $samples[$s] = (Get-FileHash $p -Algorithm SHA256).Hash }
            else { $samples[$s] = '<missing>' }
        }
    } else {
        $samples['note'] = '-SampleDir not provided; sample hashes not captured'
    }

    $manifest = [ordered]@{
        generatedAt = (Get-Date).ToString('o')
        repo = @{
            root = $RepoRoot
            branch = (git -C $RepoRoot branch --show-current)
            headCommit = (git -C $RepoRoot rev-parse HEAD)
            dirtyFiles = $dirty
        }
        backendIdentity = @{
            note = 'repo files take precedence via PYTHONPATH order in repo-backend runs; installed site-packages is the fallback runtime'
            repoFileSha256 = $repoHashes
            installedFileSha256 = $instHashes
            babeldocLockEntry = $lockEntry
        }
        interpreter = @{ path = $python; version = $pyVer }
        installedPackageVersions = $pkgVersions
        machine = @{
            cpu = $cpu; logicalProcessors = [Environment]::ProcessorCount
            totalRamGB = $ramGB; powerScheme = $power
            osVersion = [Environment]::OSVersion.VersionString
        }
        scripts = @{
            p0_baseline = Sha (Join-Path $RepoRoot 'tests\performance\p0_baseline.ps1')
            p0_probe_perprocess = Sha (Join-Path $RepoRoot 'tests\performance\p0_probe_perprocess.ps1')
            p0_probe_attribution = Sha (Join-Path $RepoRoot 'tests\performance\p0_probe_attribution.ps1')
            p0_pytest_isolated = Sha (Join-Path $RepoRoot 'tests\performance\p0_pytest_isolated.ps1')
            conftest = Sha (Join-Path $RepoRoot 'source\tests\conftest.py')
            patch = Sha (Join-Path $RepoRoot 'build\patches\babeldoc\0001-assets-upstream-env.patch')
        }
        samples = $samples
        offlinePolicy = 'translation never submitted; cache staged and per-file SHA256 verified against install home before start; every child runs the sitecustomize socket guard (non-loopback connect blocked+logged); blocked attempts during warmup recorded, post-ready attempts fail the run'
    }

    $manifest | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $RunDir 'manifest.json') -Encoding UTF8
    Write-Host ("manifest written: {0}" -f (Join-Path $RunDir 'manifest.json'))
    exit 0
} finally {
    if ($null -ne $savedPy) { $env:PYTHONPATH = $savedPy } else { Remove-Item Env:PYTHONPATH -ErrorAction SilentlyContinue }
    $env:GIT_CONFIG_COUNT = $savedGc[0]; $env:GIT_CONFIG_KEY_0 = $savedGc[1]; $env:GIT_CONFIG_VALUE_0 = $savedGc[2]
}
