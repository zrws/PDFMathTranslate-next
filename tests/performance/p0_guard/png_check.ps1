# Shared strict PNG validator v5 (ASCII only) - single source of truth.
# C3 heritage: REAL decodeability check via PIL/Pillow.
# R2 fixes: the PIL decode child runs in an ISOLATED per-child environment
# (HOME/USERPROFILE/TEMP/CWD under the caller-supplied isolated root); the
# temp PNG lives in that isolated root; no parent-environment mutation at all
# (so nothing to restore on exception paths). Isolation is MANDATORY:
# Set-PngPythonExe without -IsolatedHome is a configuration error.
#
# PS 5.1 note: ALL arithmetic uses int64 multiplication (no shift/cast).
# Validation chain: signature -> IHDR tag -> dimensions -> expected width ->
# IHDR CRC32 -> PIL open+verify+load (actual decodeability).

$script:pngCrcTable = New-Object 'long[]' 256
for ($n = 0; $n -lt 256; $n++) {
    $c = [long]$n
    for ($k = 0; $k -lt 8; $k++) {
        if (($c -band 1) -ne 0) { $c = ([long]3988292384) -bxor [long][math]::Floor($c / 2) }
        else { $c = [long][math]::Floor($c / 2) }
    }
    $script:pngCrcTable[$n] = $c
}

function Get-Crc32([byte[]]$data, [int]$start, [int]$len) {
    $crc = [long]4294967295   # 0xFFFFFFFF as positive int64
    for ($i = $start; $i -lt ($start + $len); $i++) {
        $idx = ($crc -bxor [long]$data[$i]) -band 0xFF
        $crc = $script:pngCrcTable[$idx] -bxor [long][math]::Floor($crc / 256)
    }
    $result = $crc -bxor [long]4294967295
    if ($result -lt 0) { $result += [long]4294967296 }  # wrap to unsigned
    return $result
}

function Test-PngStrict([byte[]]$b, [int]$expectWidth, [ref]$w, [ref]$hgt, [ref]$why) {
    $sig = @(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)
    if ($b.Length -lt 33) { $why.Value = 'too short'; return $false }
    for ($i = 0; $i -lt 8; $i++) { if ($b[$i] -ne $sig[$i]) { $why.Value = 'bad signature'; return $false } }
    if ($b[12] -ne 0x49 -or $b[13] -ne 0x48 -or $b[14] -ne 0x44 -or $b[15] -ne 0x52) { $why.Value = 'missing IHDR'; return $false }
    $w.Value  = [int]($b[16] * 16777216 + $b[17] * 65536 + $b[18] * 256 + $b[19])
    $hgt.Value = [int]($b[20] * 16777216 + $b[21] * 65536 + $b[22] * 256 + $b[23])
    if ($w.Value -eq 0 -or $hgt.Value -eq 0) { $why.Value = 'zero dimension'; return $false }
    if ($expectWidth -gt 0 -and [math]::Abs($w.Value - $expectWidth) -gt 2) { $why.Value = ("width {0} != expected {1}" -f $w.Value, $expectWidth); return $false }
    $crcGot = $b[29] * 16777216 + $b[30] * 65536 + $b[31] * 256 + $b[32]
    $crcCalc = Get-Crc32 $b 12 17
    if ($crcGot -ne $crcCalc) { $why.Value = ("IHDR CRC mismatch (got {0} calc {1})" -f $crcGot, $crcCalc); return $false }

    # R2: decode child must be configured with an isolated root
    if (-not $script:pngIsoHome) { $why.Value = 'png decoder not configured with -IsolatedHome (R2)'; return $false }
    $isoTmp = Join-Path $script:pngIsoHome 'pngcheck-tmp'
    New-Item -ItemType Directory -Force -Path $isoTmp | Out-Null
    $tmpPng = Join-Path $isoTmp ("pngcheck-" + [guid]::NewGuid().ToString('N').Substring(0, 12) + ".png")
    $tmpPy = Join-Path $isoTmp ("pngdecode-" + [guid]::NewGuid().ToString('N').Substring(0, 12) + ".py")
    try {
        [IO.File]::WriteAllBytes($tmpPng, $b)
        @'
import sys, json
try:
    from PIL import Image
    img = Image.open(sys.argv[1])
    img.verify()
    img2 = Image.open(sys.argv[1])
    img2.load()
    print(json.dumps({'ok': True, 'w': img2.size[0], 'h': img2.size[1]}))
except Exception as e:
    print(json.dumps({'ok': False, 'error': str(e)[:120]}))
'@ | Set-Content -Path $tmpPy -Encoding ASCII
        # R2: isolated per-child environment; NO parent env mutation
        $pinfo = [System.Diagnostics.ProcessStartInfo]::new()
        $pinfo.FileName = $script:pngPythonExe
        $pinfo.Arguments = '"' + $tmpPy + '" "' + $tmpPng + '"'
        $pinfo.WorkingDirectory = $isoTmp
        $pinfo.UseShellExecute = $false
        $pinfo.CreateNoWindow = $true
        $pinfo.RedirectStandardOutput = $true
        $pinfo.RedirectStandardError = $true
        $pinfo.EnvironmentVariables['HOME'] = $script:pngIsoHome
        $pinfo.EnvironmentVariables['USERPROFILE'] = $script:pngIsoHome
        $pinfo.EnvironmentVariables['APPDATA'] = (Join-Path $script:pngIsoHome 'AppData\Roaming')
        $pinfo.EnvironmentVariables['LOCALAPPDATA'] = (Join-Path $script:pngIsoHome 'AppData\Local')
        $pinfo.EnvironmentVariables['TEMP'] = $isoTmp
        $pinfo.EnvironmentVariables['TMP'] = $isoTmp
        $pinfo.EnvironmentVariables['XDG_CACHE_HOME'] = (Join-Path $script:pngIsoHome '.cache')
        $pinfo.EnvironmentVariables['PYTHONUTF8'] = '1'
        $pinfo.EnvironmentVariables['PYTHONPATH'] = $script:pngPythonPath
        $proc = [System.Diagnostics.Process]::Start($pinfo)
        $pSoTask = $proc.StandardOutput.ReadToEndAsync()
        $pSeTask = $proc.StandardError.ReadToEndAsync()
        [void]$proc.WaitForExit(60000)
        if (-not $proc.HasExited) {
            try { $proc.Kill() } catch { }
            $why.Value = 'decode check timed out'
            return $false
        }
        try { $decodeResult = $pSoTask.Result } catch { $decodeResult = '' }
        $jsonLine = @($decodeResult -split "`n") | Where-Object { $_ -match '^\s*\{' } | Select-Object -First 1
        if (-not $jsonLine) { $why.Value = 'decode check produced no result'; return $false }
        $d = $jsonLine | ConvertFrom-Json
        if (-not $d.ok) {
            $why.Value = ("not decodable: " + $d.error)
            return $false
        }
        if ([int]$d.w -ne $w.Value -or [int]$d.h -ne $hgt.Value) {
            $why.Value = ("decoded size {0}x{1} != IHDR {2}x{3}" -f $d.w, $d.h, $w.Value, $hgt.Value)
            return $false
        }
    } catch {
        $why.Value = ("decode check exception: " + $_.Exception.Message)
        return $false
    } finally {
        Remove-Item $tmpPng -Force -ErrorAction SilentlyContinue
        Remove-Item $tmpPy -Force -ErrorAction SilentlyContinue
    }
    return $true
}

# Configure the PNG decode child. R2: -IsolatedHome is MANDATORY; the child
# runs entirely inside it (no real-home inheritance, no parent env changes).
function Set-PngPythonExe([string]$exePath, [string]$sitePackages = '', [string]$IsolatedHome = '') {
    if (-not $IsolatedHome -or -not (Test-Path $IsolatedHome)) {
        throw 'Set-PngPythonExe: -IsolatedHome is mandatory (R2 isolation)'
    }
    $script:pngPythonExe = $exePath
    $script:pngPythonPath = $sitePackages
    $script:pngIsoHome = [IO.Path]::GetFullPath($IsolatedHome)
}
