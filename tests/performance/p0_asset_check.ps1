# BabelDOC authoritative asset integrity pre-check v2 (ASCII only, PS 5.1 safe)
# R2 fixes over v1:
#   - the METADATA python child (and the hash child) run in a per-child
#     ProcessStartInfo environment block: HOME/USERPROFILE/APPDATA/LOCALAPPDATA/
#     TEMP/PDF2ZH_HOME/PDF2ZH_CONFIG_FILE/CWD all point into an ISOLATED root
#     supplied by the caller. The calling PowerShell's real HOME is never
#     inherited. Missing -IsolatedHome => refusal (isolation_required).
#   - the child prints its EFFECTIVE paths; the helper asserts cache_folder is
#     inside the isolated root and FAILS if a real user directory shows up.
#   - failure paths all return $false with a precise reason (never total=0->true):
#       metadata_unparseable / empty_manifest / missing_category /
#       hash_tool_failed / asset_missing / asset_corrupt / isolation_violation
#
# Usage:
#   . p0_asset_check.ps1
#   Invoke-AssetCheck -CacheDir <dir> -InstallRoot <root> -IsolatedHome <isoRoot>
#     [-PythonExe <path>] [-RequireCategories a,b,c]

function Invoke-AssetCheck {
    param(
        [Parameter(Mandatory)][string]$CacheDir,
        [Parameter(Mandatory)][string]$InstallRoot,
        [Parameter(Mandatory)][string]$IsolatedHome,   # R2: caller's isolated root
        [string]$PythonExe = '',
        [string[]]$RequireCategories = @('fonts', 'models', 'cmap', 'tiktoken'),
        # --- test-only seams (M5): simulate manifest/hash-tool failures without
        # touching the locked package; never used by production entries ------
        [string]$TestMetaJsonPath = '',
        [switch]$TestHashToolFailure
    )
    if (-not $PythonExe) {
        $PythonExe = Get-ChildItem (Join-Path $InstallRoot 'uv-python') -Recurse -Filter python.exe |
            Select-Object -First 1 -ExpandProperty FullName
    }
    $sp = Join-Path $InstallRoot 'uv-tools\pdf2zh-next\Lib\site-packages'
    if (-not (Test-Path $sp) -or -not (Test-Path $CacheDir)) {
        Write-Host '[FAIL] asset check: site-packages or cache dir missing'
        return $false
    }
    if (-not (Test-Path $IsolatedHome)) {
        Write-Host '[FAIL] asset check: -IsolatedHome root does not exist (isolation mandatory, R2)'
        return $false
    }

    # --- isolated child environment (never inherits the caller's home) ------
    $isoHomeFull = [IO.Path]::GetFullPath($IsolatedHome)
    $isoWork = Join-Path $isoHomeFull 'assetcheck-work'
    $isoTmp = Join-Path $isoHomeFull 'assetcheck-tmp'
    foreach ($d in @($isoWork, $isoTmp, (Join-Path $isoHomeFull '.config\pdf2zh'))) {
        New-Item -ItemType Directory -Force -Path $d | Out-Null
    }
    $isoConfig = Join-Path $isoHomeFull '.config\pdf2zh\config.v3.toml'
    if (-not (Test-Path $isoConfig)) { Set-Content -Path $isoConfig -Value '' -Encoding ASCII }

    function New-AssetChild([string]$codeFile) {
        $pinfo = [System.Diagnostics.ProcessStartInfo]::new()
        $pinfo.FileName = $PythonExe
        $pinfo.Arguments = '"' + $codeFile + '"'
        $pinfo.WorkingDirectory = $isoWork
        $pinfo.UseShellExecute = $false
        $pinfo.CreateNoWindow = $true
        $pinfo.RedirectStandardOutput = $true
        $pinfo.RedirectStandardError = $true
        $pinfo.EnvironmentVariables['HOME'] = $isoHomeFull
        $pinfo.EnvironmentVariables['USERPROFILE'] = $isoHomeFull
        $pinfo.EnvironmentVariables['APPDATA'] = (Join-Path $isoHomeFull 'AppData\Roaming')
        $pinfo.EnvironmentVariables['LOCALAPPDATA'] = (Join-Path $isoHomeFull 'AppData\Local')
        $pinfo.EnvironmentVariables['TEMP'] = $isoTmp
        $pinfo.EnvironmentVariables['TMP'] = $isoTmp
        $pinfo.EnvironmentVariables['XDG_CACHE_HOME'] = (Join-Path $isoHomeFull '.cache')
        $pinfo.EnvironmentVariables['PDF2ZH_HOME'] = $isoHomeFull
        $pinfo.EnvironmentVariables['PDF2ZH_CONFIG_FILE'] = $isoConfig
        $pinfo.EnvironmentVariables['PYTHONUTF8'] = '1'
        $pinfo.EnvironmentVariables['PYTHONPATH'] = $sp
        # strip inherited proxy/pdf2zh overrides except the whitelist
        $strip = @()
        foreach ($k in $pinfo.EnvironmentVariables.Keys) {
            if (($k -like 'PDF2ZH_*' -or $k -like 'BABELDOC_*' -or $k -like '*_PROXY') -and
                $k -notin @('PDF2ZH_HOME','PDF2ZH_CONFIG_FILE','BABELDOC_ASSETS_UPSTREAM','NO_PROXY','no_proxy')) {
                $strip += $k
            }
        }
        foreach ($k in $strip) { $pinfo.EnvironmentVariables.Remove($k) | Out-Null }
        return $pinfo
    }

    # --- metadata (isolated child; test seam can substitute a file) --------
    $metaOut = ''
    if ($TestMetaJsonPath) {
        if (-not (Test-Path $TestMetaJsonPath)) {
            Write-Host '[FAIL] asset check: -TestMetaJsonPath given but file missing (test setup error)'
            return $false
        }
        $metaOut = [IO.File]::ReadAllText($TestMetaJsonPath)
        Write-Host '[meta] (test seam: metadata injected from file)'
        $metaExit = 0
    } else {
        $code = @'
import sys, json, os
from babeldoc.assets.assets import generate_all_assets_file_list
from babeldoc.const import CACHE_FOLDER
file_list = generate_all_assets_file_list()
print(json.dumps({
    "file_list": file_list,
    "cache_folder": str(CACHE_FOLDER),
    "babeldoc_version": __import__("babeldoc").__version__,
    "effective_home": os.environ.get("HOME", ""),
    "effective_userprofile": os.environ.get("USERPROFILE", ""),
}))
'@
        $tmp = Join-Path $isoTmp ("assetcheck-meta-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.py')
        Set-Content -Path $tmp -Value $code -Encoding ASCII
        $pinfo = New-AssetChild $tmp
        $proc = [System.Diagnostics.Process]::Start($pinfo)
        # async reads FIRST: babeldoc prints a lot; a full pipe buffer would
        # deadlock a child that we only read AFTER WaitForExit
        $soTask = $proc.StandardOutput.ReadToEndAsync()
        $seTask = $proc.StandardError.ReadToEndAsync()
        [void]$proc.WaitForExit(180000)
        if (-not $proc.HasExited) {
            try { $proc.Kill() } catch { }
            Write-Host '[FAIL] asset check: metadata child timed out (metadata_timeout)'
            return $false
        }
        $metaExit = $proc.ExitCode
        try { $metaOut = $soTask.Result } catch { $metaOut = '' }
        try { $metaErr = $seTask.Result } catch { $metaErr = '' }
        foreach ($ln in @($metaOut)) { if ($ln) { Write-Host ("[meta] " + $ln) } }
        if ($metaErr) { $metaErr | Set-Content (Join-Path $isoTmp 'meta-stderr.txt') -Encoding UTF8 }
        if ($metaExit -ne 0) {
            Write-Host ("[FAIL] asset check: metadata child exit={0} (metadata_failed)" -f $metaExit)
            return $false
        }
    }

    $jsonLine = @($metaOut -split "`n") | Where-Object { $_ -match '^\s*\{' } | Select-Object -First 1
    if (-not $jsonLine) {
        Write-Host '[FAIL] asset check: could not read babeldoc asset metadata (metadata_unparseable)'
        return $false
    }
    try { $meta = $jsonLine | ConvertFrom-Json } catch {
        Write-Host ("[FAIL] asset check: metadata JSON parse error (metadata_unparseable): " + $_.Exception.Message)
        return $false
    }

    # R2: assert the child's EFFECTIVE paths are inside the isolated root
    $cacheFolder = "$($meta.cache_folder)"
    $effHome = "$($meta.effective_home)"
    Write-Host ("[asset-meta] babeldoc {0}, cache_folder={1}, effective HOME={2}" -f $meta.babeldoc_version, $cacheFolder, $effHome)
    # machine artifact (console-redirected lines can be width-truncated in PS 5.1;
    # downstream assertions must read THIS file, not the console log)
    try {
        [ordered]@{
            babeldoc_version = "$($meta.babeldoc_version)"
            cache_folder = $cacheFolder
            effective_home = $effHome
            isolated_root = $isoHomeFull
        } | ConvertTo-Json | Set-Content (Join-Path $isoTmp 'assetcheck-meta.json') -Encoding UTF8
    } catch { Write-Host '[warn] cannot write assetcheck-meta.json artifact' }
    $realUser = [Environment]::GetEnvironmentVariable('USERPROFILE')
    # R2 isolation assertions apply to REAL metadata children; the test seam
    # (TestMetaJsonPath) injects synthetic manifests whose paths are irrelevant
    if (-not $TestMetaJsonPath) {
        if ($cacheFolder -notlike ($isoHomeFull + '*')) {
            Write-Host ("[FAIL] asset check: cache_folder is NOT inside the isolated root (isolation_violation): {0}" -f $cacheFolder)
            return $false
        }
        if ($effHome -notlike ($isoHomeFull + '*')) {
            Write-Host ("[FAIL] asset check: child HOME is NOT the isolated root (isolation_violation): {0}" -f $effHome)
            return $false
        }
        if (($cacheFolder -like ($realUser + '*')) -or ($effHome -like ($realUser + '*'))) {
            Write-Host '[FAIL] asset check: real user directory leaked into child (isolation_violation)'
            return $false
        }
    }

    # --- manifest failure paths (never total=0 -> true) ----------------------
    $totalListed = 0
    foreach ($cat in $RequireCategories) {
        $items = $meta.file_list.PSObject.Properties[$cat]
        if ($null -eq $items -or $null -eq $items.Value) {
            Write-Host ("[FAIL] asset check: required category missing from manifest (missing_category): {0}" -f $cat)
            return $false
        }
        $totalListed += @($items.Value).Count
    }
    if ($totalListed -eq 0) {
        Write-Host '[FAIL] asset check: manifest lists zero required assets (empty_manifest)'
        return $false
    }

    # --- per-file SHA3-256 verification with an isolated hash child ----------
    $allOk = $true
    $total = 0; $verified = 0; $missing = 0; $corrupt = 0
    $hashTool = Join-Path $isoTmp 'hash_tool.py'
    @'
import hashlib, sys, json
try:
    h = hashlib.sha3_256()
    with open(sys.argv[1], 'rb') as f:
        for chunk in iter(lambda: f.read(1024*1024), b''):
            h.update(chunk)
    print(json.dumps({"sha3_256": h.hexdigest()}))
except Exception as e:
    print(json.dumps({"error": str(e)[:200]}))
'@ | Set-Content -Path $hashTool -Encoding ASCII
    foreach ($cat in $RequireCategories) {
        $items = @($meta.file_list.PSObject.Properties[$cat].Value)
        foreach ($item in $items) {
            $total++
            $f = Join-Path $CacheDir (Join-Path $cat $item.name)
            if (-not (Test-Path $f)) {
                Write-Host ("[FAIL] {0}/{1} MISSING (asset_missing)" -f $cat, $item.name)
                $missing++; $allOk = $false; continue
            }
            # M5 test seam: simulate a hash-tool failure for the FIRST item only
            if ($TestHashToolFailure) {
                Write-Host ("[FAIL] {0}/{1} hash tool failed (hash_tool_failed), test seam" -f $cat, $item.name)
                $corrupt++; $allOk = $false
                if ($total -ge 1) { break }
                continue
            }
            $hp = New-AssetChild $hashTool
            $hp.Arguments = '"' + $hashTool + '" "' + $f + '"'
            $hproc = [System.Diagnostics.Process]::Start($hp)
            $hSoTask = $hproc.StandardOutput.ReadToEndAsync()
            [void]$hproc.WaitForExit(60000)
            if (-not $hproc.HasExited) {
                try { $hproc.Kill() } catch { }
                Write-Host ("[FAIL] {0}/{1} hash child timed out (hash_tool_failed)" -f $cat, $item.name)
                $corrupt++; $allOk = $false; continue
            }
            try { $hOut = $hSoTask.Result } catch { $hOut = '' }
            $hLine = @($hOut -split "`n") | Where-Object { $_ -match '^\s*\{' } | Select-Object -First 1
            if ($hproc.ExitCode -ne 0 -or -not $hLine) {
                Write-Host ("[FAIL] {0}/{1} hash tool failed (hash_tool_failed), exit={2}" -f $cat, $item.name, $hproc.ExitCode)
                $corrupt++; $allOk = $false; continue
            }
            try { $h = $hLine | ConvertFrom-Json } catch {
                Write-Host ("[FAIL] {0}/{1} hash output unparseable (hash_tool_failed)" -f $cat, $item.name)
                $corrupt++; $allOk = $false; continue
            }
            if ($h.PSObject.Properties['error']) {
                Write-Host ("[FAIL] {0}/{1} hash tool error (hash_tool_failed): {2}" -f $cat, $item.name, $h.error)
                $corrupt++; $allOk = $false; continue
            }
            if ($h.sha3_256 -ne $item.sha3_256) {
                Write-Host ("[FAIL] {0}/{1} SHA3-256 MISMATCH (asset_corrupt, expected {2}, got {3})" -f $cat, $item.name, $item.sha3_256, $h.sha3_256)
                $corrupt++; $allOk = $false
            } else {
                $verified++
            }
        }
    }
    Write-Host ("[asset-check] total={0} verified={1} missing={2} corrupt={3} => {4}" -f $total, $verified, $missing, $corrupt, $(if ($allOk) { 'PASS' } else { 'FAIL' }))
    return $allOk
}
