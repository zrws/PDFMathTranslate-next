$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Launcher = Join-Path $Root 'launcher'
$Publish = Join-Path $Launcher 'publish'
$OutputExe = Join-Path $Root 'PDFMathTranslate.exe'

$Dotnet = $null
$LocalDotnet = Join-Path (Split-Path -Parent $Root) '.dotnet-sdk\dotnet.exe'
if (Test-Path -LiteralPath $LocalDotnet) {
    $Dotnet = $LocalDotnet
} elseif (Get-Command dotnet -ErrorAction SilentlyContinue) {
    $Dotnet = (Get-Command dotnet).Source
}
if (-not $Dotnet) {
    throw '未找到 dotnet SDK。请安装 .NET 8 SDK 后重新运行。'
}

& $Dotnet publish (Join-Path $Launcher 'PDFMathTranslateLauncher.csproj') `
    --configuration Release `
    --runtime win-x64 `
    --self-contained true `
    --output $Publish

$BuiltExe = Join-Path $Publish 'PDFMathTranslate.exe'
if (-not (Test-Path -LiteralPath $BuiltExe)) {
    throw "构建完成但未找到 $BuiltExe"
}

Copy-Item -LiteralPath $BuiltExe -Destination $OutputExe -Force
Write-Host "已生成：$OutputExe"
Write-Host '请复制整个 PDFMathTranslate-next 文件夹到另一台 Windows 电脑，不要只复制 EXE。'
