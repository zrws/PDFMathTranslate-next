$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$env:USERPROFILE = Join-Path $Root "home"
$env:PATH = (Join-Path $Root "bin") + ";" + $env:PATH
$env:BABELDOC_ASSETS_UPSTREAM = "modelscope"

$DefaultConfig = Join-Path $Root "home\.config\pdf2zh\config.v3.toml"
$HasConfigArg = $false
foreach ($Arg in $args) {
    if ($Arg -eq "--config-file") {
        $HasConfigArg = $true
        break
    }
}

if ((Test-Path -LiteralPath $DefaultConfig) -and -not $HasConfigArg) {
    & (Join-Path $Root "bin\pdf2zh.exe") --config-file $DefaultConfig @args
} else {
    & (Join-Path $Root "bin\pdf2zh.exe") @args
}
exit $LASTEXITCODE
