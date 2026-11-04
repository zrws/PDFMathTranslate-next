param(
    [Parameter(Mandatory=$true)][string]$DotnetExe,
    [Parameter(Mandatory=$true)][string]$UvExe,
    [Parameter(Mandatory=$true)][string]$PythonRoot,
    [string]$IsccExe,
    [string]$Version='2.9.0',
    [ValidateSet('preview','stable')][string]$Channel='preview',
    [string]$TestAppId='',
    [string]$TestGroup='',
    [switch]$Offline,
    [switch]$SkipInstaller
)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $repo
$DotnetExe=(Resolve-Path -LiteralPath $DotnetExe).Path
$UvExe=(Resolve-Path -LiteralPath $UvExe).Path
$PythonRoot=(Resolve-Path -LiteralPath $PythonRoot).Path
$python=Join-Path $PythonRoot 'python.exe'
if(!(Test-Path -LiteralPath $python)){throw '需要 CPython 3.12.13 完整运行目录'}
if((& $python --version) -ne 'Python 3.12.13'){throw 'Python 版本与锁不符'}
if((& $DotnetExe --version) -ne '10.0.403'){throw '.NET SDK 版本与 global.json 不符'}
if((& $UvExe --version) -notmatch '^uv 0\.13\.7\b'){throw '需要锁定 uv 0.13.7'}
$id=[guid]::NewGuid().ToString('N').Substring(0,12)
$build=Join-Path $repo ('.local/build-native-'+$id)
$payload=Join-Path $build 'payload'
$venv=Join-Path $build 'clean-venv'
$output=Join-Path $repo ('dist/native-'+$id)
New-Item -ItemType Directory -Path $payload,$output | Out-Null
$env:UV_CACHE_DIR=Join-Path $repo '.local/uv-cache'
$env:DOTNET_CLI_HOME=Join-Path $repo '.local/dotnet-home'
$env:NUGET_PACKAGES=Join-Path $repo '.local/nuget-packages'
$env:DOTNET_CLI_TELEMETRY_OPTOUT='1'
$env:PYTHONDONTWRITEBYTECODE='1'
$env:PYTHONUTF8='1'
$env:PYTHONNOUSERSITE='1'
foreach($key in @('SSL_CERT_FILE','SSL_CERT_DIR')){if([Environment]::GetEnvironmentVariable($key) -and !(Test-Path -LiteralPath ([Environment]::GetEnvironmentVariable($key)))){[Environment]::SetEnvironmentVariable($key,$null,'Process')}}
& $UvExe venv --python $python --no-python-downloads $venv
if($LASTEXITCODE){throw '洁净 venv 创建失败'}
$uvArgs=@('pip','sync','--python',(Join-Path $venv 'Scripts/python.exe'),'--require-hashes','--no-python-downloads','--no-build', (Join-Path $repo 'build/dependency-locks/windows-py312.txt'))
if($Offline){$uvArgs+='--offline'}
& $UvExe @uvArgs
if($LASTEXITCODE){throw '哈希锁依赖同步失败'}
& $DotnetExe restore desktop/PDFMathTranslate.Desktop --locked-mode --disable-parallel --ignore-failed-sources --configfile build/NuGet.Config
if($LASTEXITCODE){throw '锁定 NuGet 还原失败'}
& $DotnetExe publish desktop/PDFMathTranslate.Desktop -c Release -r win-x64 --self-contained false --no-restore -o $payload
if($LASTEXITCODE){throw 'WPF Release 构建失败'}
function Copy-Tree([string]$From,[string]$To,[string[]]$Extra=@()){
    & robocopy $From $To /E /MT:4 /R:2 /W:1 /NFL /NDL /NJH /NJS /NP /XF *.pyc *.map /XD __pycache__ .pytest_cache tests test @Extra
    if($LASTEXITCODE -lt 0 -or $LASTEXITCODE -ge 8){throw "复制失败：$From，退出码 $LASTEXITCODE"}
}
Copy-Tree $PythonRoot (Join-Path $payload ('uv-python/'+(Split-Path -Leaf $PythonRoot)))
$packages=Join-Path $payload 'uv-tools/pdf2zh-next/Lib/site-packages'
Copy-Tree (Join-Path $venv 'Lib/site-packages') $packages
& $python build/apply-engine-patches.py --site-packages $packages
if($LASTEXITCODE){throw 'BabelDOC 锁定补丁失败'}
& $python build/copy-product-source.py --target (Join-Path $packages 'pdf2zh_next') --report (Join-Path $output 'product-source.json')
if($LASTEXITCODE){throw '产品源码集合或哈希核验失败'}
# The optional Gradio UI is not the shipped native interface. This matches the
# previous slim distribution; it is not counted as a new size reduction.
$removed=@()
& (Join-Path $venv 'Scripts/python.exe') build/package-audit.py --site-packages $packages --output (Join-Path $output 'dependency-graph.json')
if($LASTEXITCODE){throw '运行依赖图审计失败'}
Get-ChildItem -LiteralPath $packages -Directory | Where-Object {$_.Name -in @('gradio','gradio_client','gradio_pdf') -or $_.Name -match '^gradio(-|_client-|_pdf-).*\.dist-info$'} | ForEach-Object {
    $target=$_.FullName
    if(!$target.StartsWith($packages+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw '删除路径越界'}
    $removed+=@{path=$_.Name;reason='optional Gradio UI; same exclusion as prior slim build'}
    Remove-Item -LiteralPath $target -Recurse -Force
}
# Remove only dependencies introduced by the test input. The graph audit above
# fails closed if a non-test package requires one without an extra marker.
Get-ChildItem -LiteralPath $packages -Directory | Where-Object {$_.Name -in @('pytest','_pytest','pluggy','iniconfig') -or $_.Name -match '^(pytest|pluggy|iniconfig)-.*\.dist-info$'} | ForEach-Object {
    $target=$_.FullName
    if(!$target.StartsWith($packages+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw '删除路径越界'}
    $removed+=@{path=$_.Name;reason='test-only graph verified';bytes=(Get-ChildItem -LiteralPath $target -File -Recurse|Measure-Object Length -Sum).Sum}
    Remove-Item -LiteralPath $target -Recurse -Force
}
Get-ChildItem -LiteralPath (Join-Path $packages 'cv2') -File -Filter 'opencv_videoio_ffmpeg*_64.dll' | ForEach-Object {
    $removed+=@{path=('cv2/'+$_.Name);reason='unused video codec; PDF image pipeline separately tested';bytes=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}
    Remove-Item -LiteralPath $_.FullName
}
$sdkRoot=Split-Path -Parent $DotnetExe
Copy-Tree (Join-Path $sdkRoot 'host') (Join-Path $payload 'dotnet/host')
foreach($framework in @('Microsoft.NETCore.App','Microsoft.WindowsDesktop.App')){
    $runtime=Get-ChildItem -LiteralPath (Join-Path $sdkRoot ('shared/'+$framework)) -Directory | Sort-Object {[version]$_.Name} -Descending | Select-Object -First 1
    if(!$runtime -or ([version]$runtime.Name).Major -ne 10){throw '缺少私有 .NET 10 运行时'}
    Copy-Tree $runtime.FullName (Join-Path $payload ('dotnet/shared/'+$framework+'/'+$runtime.Name))
}
Copy-Item -LiteralPath $DotnetExe -Destination (Join-Path $payload 'dotnet/dotnet.exe')
Copy-Item -LiteralPath (Join-Path $repo 'source/LICENSE') -Destination (Join-Path $payload 'LICENSE')
$licenses=Join-Path $payload 'licenses';New-Item -ItemType Directory -Path $licenses|Out-Null
foreach($file in @('LICENSE.txt','ThirdPartyNotices.txt')){Copy-Item -LiteralPath (Join-Path $sdkRoot $file) -Destination (Join-Path $licenses ('dotnet-'+$file))}
foreach($package in @(@('wpf-ui','4.3.0','LICENSE.md'),@('communitytoolkit.mvvm','8.4.2','License.md'))){
    $packageRoot=Join-Path $env:NUGET_PACKAGES ($package[0]+'/'+$package[1])
    Copy-Item -LiteralPath (Join-Path $packageRoot $package[2]) -Destination (Join-Path $licenses ($package[0]+'-LICENSE.md'))
    Copy-Item -LiteralPath (Join-Path $packageRoot 'ThirdPartyNotices.txt') -Destination (Join-Path $licenses ($package[0]+'-ThirdPartyNotices.txt'))
}
Copy-Item -LiteralPath (Join-Path $repo 'build/licenses/XamlFlair-LICENSE.txt') -Destination (Join-Path $licenses 'XamlFlair-LICENSE.txt')
foreach($package in @(@('system.reactive','5.0.0'),@('microsoft.extensions.logging.abstractions','10.0.0'),@('microsoft.extensions.dependencyinjection.abstractions','10.0.0'))){
    $metadata=Join-Path $env:NUGET_PACKAGES ($package[0]+'/'+$package[1]+'/'+$package[0]+'.nuspec')
    Copy-Item -LiteralPath $metadata -Destination (Join-Path $licenses ($package[0]+'.nuspec'))
}
Copy-Item -LiteralPath (Join-Path $repo 'build/licenses/System.Reactive-LICENSE.txt') -Destination (Join-Path $licenses 'System.Reactive-LICENSE.txt')
foreach($file in @('Microsoft.Extensions-LICENSE.txt','Microsoft.Extensions-NOTICE.txt')){
    Copy-Item -LiteralPath (Join-Path $repo ('build/licenses/'+$file)) -Destination (Join-Path $licenses $file)
}
foreach($package in @('microsoft.extensions.logging.abstractions','microsoft.extensions.dependencyinjection.abstractions')){
    Copy-Item -LiteralPath (Join-Path $env:NUGET_PACKAGES ($package+'/10.0.0/THIRD-PARTY-NOTICES.TXT')) -Destination (Join-Path $licenses ($package+'-ThirdPartyNotices.txt'))
}
foreach($name in @('LICENSE','README.md')){if(Test-Path -LiteralPath (Join-Path $repo $name)){Copy-Item -LiteralPath (Join-Path $repo $name) -Destination $payload}}
Copy-Item -LiteralPath (Join-Path $repo 'build/THIRD_PARTY_NOTICES.md') -Destination $payload
@{version=$Version;channel=$Channel} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $payload 'version.json') -Encoding utf8
# Exact ownership list supports safe obsolete-file cleanup on upgrades. Never
# enumerate user home/output/cache, and never add a recursive InstallDelete.
$owned=Get-ChildItem -LiteralPath $payload -Recurse -File | Sort-Object FullName | ForEach-Object {
    $_.FullName.Substring($payload.Length+1)+'|'+(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
}
[IO.File]::WriteAllLines((Join-Path $payload 'owned-files.tsv'),$owned,[Text.UTF8Encoding]::new($true))
$installer=$null
if(!$SkipInstaller){
    if(!$IsccExe){throw '请明确提供项目本地 Inno Setup ISCC 路径'}
    $isccArgs=@("/DAppVersion=$Version","/DPayloadRoot=$payload","/DInstallerOutputDir=$output")
    if($TestAppId){$isccArgs+="/DAppGuid=$TestAppId"}
    if($TestGroup){$isccArgs+="/DAppGroup=$TestGroup"}
    & $IsccExe @isccArgs (Join-Path $PSScriptRoot 'installer.iss')
    if($LASTEXITCODE){throw '中文安装器编译失败'}
    $installer=Join-Path $output "PDFMathTranslate-Setup-$Version.exe"
}
$report=[ordered]@{schema=2;id=$id;version=$Version;channel=$Channel;source_commit=(& git rev-parse HEAD);source_dirty=[bool](& git diff --name-only HEAD -- source desktop launcher build global.json);sdk=(& $DotnetExe --version);python=(& $python --version);payload=$payload;payload_files=@(Get-ChildItem -LiteralPath $payload -File -Recurse).Count;payload_bytes=(Get-ChildItem -LiteralPath $payload -File -Recurse | Measure-Object Length -Sum).Sum;removed=$removed;lock_sha256=(Get-FileHash build/dependency-locks/windows-py312.txt).Hash;patch_lock_sha256=(Get-FileHash build/patches/babeldoc/patch-lock.json).Hash;nuget_lock_sha256=(Get-FileHash desktop/PDFMathTranslate.Desktop/packages.lock.json).Hash;owned_manifest_sha256=(Get-FileHash (Join-Path $payload 'owned-files.tsv')).Hash;product_source_report_sha256=(Get-FileHash (Join-Path $output 'product-source.json')).Hash;installer=$installer}
if($installer){$report.installer_bytes=(Get-Item -LiteralPath $installer).Length;$report.installer_sha256=(Get-FileHash -LiteralPath $installer).Hash}
$report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $output 'build-report.json') -Encoding utf8
$report | ConvertTo-Json -Depth 5
# No publication, no formal latest.json, no deletion of build evidence.
