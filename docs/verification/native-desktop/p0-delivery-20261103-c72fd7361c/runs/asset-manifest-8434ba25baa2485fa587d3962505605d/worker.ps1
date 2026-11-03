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
