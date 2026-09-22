$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Python = Join-Path $Root "uv-tools\pdf2zh-next\Scripts\python.exe"

$HasPortArg = $false
foreach ($Arg in $args) {
    if ($Arg -eq "--server-port") {
        $HasPortArg = $true
        break
    }
}

if ($HasPortArg) {
    & $Python -u (Join-Path $Root "start-gui-direct.py") @args
} else {
    & $Python -u (Join-Path $Root "start-gui-direct.py") --server-port 7860 @args
}
exit $LASTEXITCODE
