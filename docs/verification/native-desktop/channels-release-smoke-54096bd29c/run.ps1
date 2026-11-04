param([Parameter(Mandatory=$true)][string]$Payload)
$ErrorActionPreference='Stop'
$taskRoot=$PSScriptRoot
if(Test-Path -LiteralPath (Join-Path $taskRoot 'result.json')){throw 'Refuse evidence reuse'}
$taskPayload=(Resolve-Path -LiteralPath $Payload).Path
$taskRepo=(Resolve-Path -LiteralPath (Join-Path $taskRoot '../../../..')).Path
$taskOwnedHome=Join-Path $taskRepo ('.local/release-smoke-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $taskOwnedHome | Out-Null
$taskInfo=[Diagnostics.ProcessStartInfo]::new((Join-Path $taskPayload 'PDFMathTranslate.exe'))
$taskInfo.UseShellExecute=$false
$taskInfo.WorkingDirectory=$taskOwnedHome
foreach($taskKey in @($taskInfo.Environment.Keys)){
    if($taskKey -match '^(PDF2ZH_|BABELDOC_)'){$taskInfo.Environment.Remove($taskKey)|Out-Null}
}
foreach($taskEntry in @{
    PDF2ZH_HOME=$taskOwnedHome;PDF2ZH_APP_ROOT=$taskPayload;PDF2ZH_RUNTIME_ROOT=$taskPayload
    PYTHONDONTWRITEBYTECODE='1';PYTHONNOUSERSITE='1';PYTHONUTF8='1'
    HTTP_PROXY='http://127.0.0.1:9';HTTPS_PROXY='http://127.0.0.1:9';ALL_PROXY='http://127.0.0.1:9';NO_PROXY='127.0.0.1,localhost,::1'
    HOME=$taskOwnedHome;USERPROFILE=$taskOwnedHome;APPDATA=(Join-Path $taskOwnedHome 'AppData/Roaming');LOCALAPPDATA=(Join-Path $taskOwnedHome 'AppData/Local');TEMP=(Join-Path $taskOwnedHome 'tmp');TMP=(Join-Path $taskOwnedHome 'tmp')
}.GetEnumerator()){$taskInfo.Environment[$taskEntry.Key]=$taskEntry.Value}
foreach($taskDir in @('AppData/Roaming','AppData/Local','tmp')){New-Item -ItemType Directory -Path (Join-Path $taskOwnedHome $taskDir)|Out-Null}
$taskResult=[ordered]@{
    scope='Release EXE process/window-handle and unauthenticated control listener smoke; no OS input, screenshot, authenticated health or translation assertion'
    source_commit=(& git -C $taskRepo rev-parse HEAD)
    driver_sha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash
    executable=(Join-Path $taskPayload 'PDFMathTranslate.exe')
    executable_sha256=(Get-FileHash -LiteralPath (Join-Path $taskPayload 'PDFMathTranslate.exe')).Hash
    dll_sha256=(Get-FileHash -LiteralPath (Join-Path $taskPayload 'PDFMathTranslate.dll')).Hash
    private_dotnet=Join-Path $taskPayload 'dotnet'
    home=$taskOwnedHome
    passed=$false
    main_window_handle=0
    unauthenticated_health_status=$null
    controller_terminated=$false
    children=@()
}
$taskProcess=$null
$taskChildren=@()
try{
    $taskProcess=[Diagnostics.Process]::Start($taskInfo)
    $taskResult.pid=$taskProcess.Id
    $taskResult.started_at=$taskProcess.StartTime.ToString('o')
    $taskDeadline=[DateTime]::UtcNow.AddSeconds(55)
    while([DateTime]::UtcNow -lt $taskDeadline){
        $taskProcess.Refresh()
        if($taskProcess.HasExited){throw 'Release process exited before smoke assertions'}
        $taskResult.main_window_handle=$taskProcess.MainWindowHandle.ToInt64()
        $taskCandidates=@(Get-CimInstance Win32_Process -Filter ('ParentProcessId = '+$taskProcess.Id))
        foreach($taskCandidate in $taskCandidates){
            if($taskCandidate.CreationDate -lt $taskProcess.StartTime -or !$taskCandidate.ExecutablePath){continue}
            if(!$taskCandidate.ExecutablePath.StartsWith((Join-Path $taskPayload 'uv-python')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){continue}
            $taskChild=Get-Process -Id $taskCandidate.ProcessId -ErrorAction SilentlyContinue
            if(!$taskChild -or [Math]::Abs(($taskChild.StartTime-$taskCandidate.CreationDate).TotalMilliseconds) -gt 10){continue}
            $taskChildren=@($taskChild)
            $taskResult.children=@(@{pid=$taskChild.Id;started_at=$taskChild.StartTime.ToString('o');path=$taskChild.Path;parent_pid=$taskProcess.Id})
            $taskPorts=@(Get-NetTCPConnection -State Listen -OwningProcess $taskChild.Id -ErrorAction SilentlyContinue | Where-Object LocalAddress -eq '127.0.0.1')
            foreach($taskPort in $taskPorts){
                $taskHttp=[Net.Http.HttpClient]::new([Net.Http.HttpClientHandler]@{UseProxy=$false;AllowAutoRedirect=$false})
                $taskHttp.Timeout=[TimeSpan]::FromSeconds(3)
                try{
                    $taskResponse=$taskHttp.GetAsync(('http://127.0.0.1:'+$taskPort.LocalPort+'/api/health')).GetAwaiter().GetResult()
                    $taskResult.unauthenticated_health_status=[int]$taskResponse.StatusCode
                    $taskResult.control_port=$taskPort.LocalPort
                    $taskResponse.Dispose()
                }catch{}finally{$taskHttp.Dispose()}
            }
        }
        if($taskResult.main_window_handle -ne 0 -and $taskResult.unauthenticated_health_status -eq 401){break}
        Start-Sleep -Milliseconds 250
    }
    if($taskResult.main_window_handle -eq 0 -or $taskResult.unauthenticated_health_status -ne 401){throw 'Release window/listener smoke assertions not observed'}
    $taskResult.runtime_module_paths=@($taskProcess.Modules | Where-Object ModuleName -in 'hostfxr.dll','hostpolicy.dll','coreclr.dll' | Select-Object -ExpandProperty FileName)
    $taskRuntimePrefix=(Join-Path $taskPayload 'dotnet')+[IO.Path]::DirectorySeparatorChar
    $taskResult.private_coreclr_loaded=@($taskResult.runtime_module_paths | Where-Object { [IO.Path]::GetFileName($_) -eq 'coreclr.dll' -and $_.StartsWith($taskRuntimePrefix,[StringComparison]::OrdinalIgnoreCase) }).Count -eq 1
    if(!$taskResult.private_coreclr_loaded){throw 'Private packaged CLR not observed in Release process'}
    $taskResult.passed=$true
}catch{
    $taskResult.error=$_.Exception.Message
}finally{
    if($taskProcess){
        if(!$taskProcess.HasExited){$taskProcess.Kill();$taskResult.controller_terminated=$true}
        $taskProcess.WaitForExit()
        $taskResult.main_actual_exit=$taskProcess.ExitCode
        $taskResult.ended_at=(Get-Date -Format o)
    }
    $taskResidual=@()
    foreach($taskChild in $taskChildren){
        try{if(!$taskChild.WaitForExit(5000)){$taskResidual+=@{pid=$taskChild.Id;started_at=$taskChild.StartTime.ToString('o')}}}catch{}
    }
    $taskResult.observed_child_residuals=$taskResidual
    $taskResult.passed=$taskResult.passed -and $taskResidual.Count -eq 0
    $taskResult | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $taskRoot 'result.json') -Encoding utf8
}
if(!$taskResult.passed){exit 1}
