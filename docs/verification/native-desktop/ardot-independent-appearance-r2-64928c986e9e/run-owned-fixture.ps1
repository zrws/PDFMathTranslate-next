#requires -Version 7.0
param([Parameter(Mandatory=$true)][string]$EvidenceRoot)
$ErrorActionPreference='Stop'
$repo='D:\student\翻译\PDFMathTranslate-next'
$EvidenceRoot=[IO.Path]::GetFullPath($EvidenceRoot)
if($EvidenceRoot -ne (Join-Path $repo 'docs/verification/native-desktop/ardot-independent-appearance-r2-64928c986e9e')){throw 'Only this reviewer-owned evidence root is allowed'}
$scenario=Join-Path $EvidenceRoot 'scenario.json'
$before=Get-Content -LiteralPath (Join-Path $EvidenceRoot 'fixture-before.json') -Raw -Encoding UTF8|ConvertFrom-Json
$link=Get-Item -LiteralPath $before.link -Force
if(($link.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 -or $link.Target -ne $before.target){throw 'Fixture link identity changed'}
$sentinel=Join-Path $before.target 'appearance.json'
if((Get-FileHash -LiteralPath $sentinel).Hash -ne $before.sentinel_sha256){throw 'Fixture sentinel changed before launch'}
if(Test-Path -LiteralPath (Join-Path $EvidenceRoot 'ui-run')){throw 'Refuse reused UI output'}
$exe=Join-Path $repo '.local/ui-ardot-components-a/PDFMathTranslate.exe'
$dll=[IO.Path]::ChangeExtension($exe,'.dll')
$profile=Get-Content -LiteralPath (Join-Path (Split-Path -Parent $exe) 'development-run.json') -Raw -Encoding UTF8|ConvertFrom-Json
$pythonPrefix=[IO.Path]::GetFullPath((Join-Path $profile.PDF2ZH_RUNTIME_ROOT 'uv-python')).TrimEnd('\')+'\'
$conhost=Join-Path $env:WINDIR 'System32/conhost.exe'
function Allowed-Image([string]$Path){
    if(!$Path){return $false}
    $full=[IO.Path]::GetFullPath($Path)
    return $full.Equals($exe,[StringComparison]::OrdinalIgnoreCase) -or $full.Equals($conhost,[StringComparison]::OrdinalIgnoreCase) -or ($full.StartsWith($pythonPrefix,[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($full) -in @('python.exe','pythonw.exe'))
}
function Live-Identity($Identity){
    $live=$null
    try{
        $live=[Diagnostics.Process]::GetProcessById($Identity.pid)
        return $live.StartTime.ToUniversalTime().Ticks -eq $Identity.utc_ticks -and $live.MainModule.FileName.Equals($Identity.path,[StringComparison]::OrdinalIgnoreCase)
    }catch [ArgumentException]{return $false}catch [InvalidOperationException]{return $false}
    finally{if($live){$live.Dispose()}}
}
$outcome=Join-Path $EvidenceRoot 'driver-observed.json'
if(Test-Path -LiteralPath $outcome){throw 'Refuse reused driver observation'}
$info=[Diagnostics.ProcessStartInfo]::new($exe)
$info.WorkingDirectory=Split-Path -Parent $exe
$info.UseShellExecute=$false
$info.CreateNoWindow=$true
$info.RedirectStandardOutput=$true
$info.RedirectStandardError=$true
$info.ArgumentList.Add('--ui-test')
$info.ArgumentList.Add($scenario)
$p=[Diagnostics.Process]::new()
$p.StartInfo=$info
$observed=@{
    scope='Independent fixture supplied to production DEBUG WPF verification entry; not OS input automation'
    source_commit=(& git -C $repo rev-parse HEAD)
    observer_started=(Get-Date).ToString('o')
    argv=@($exe,'--ui-test',$scenario)
    executable_sha256=(Get-FileHash -LiteralPath $exe).Hash
    dll_sha256=(Get-FileHash -LiteralPath $dll).Hash
    profile_sha256=(Get-FileHash -LiteralPath (Join-Path (Split-Path -Parent $exe) 'development-run.json')).Hash
    scenario_sha256=(Get-FileHash -LiteralPath $scenario).Hash
    driver_sha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash
    sentinel_before_sha256=(Get-FileHash -LiteralPath $sentinel).Hash
}
$timedOut=$false
$identities=@{}
$rejectedStale=0
$rejectedUnexpected=0
try{
    if(!$p.Start()){throw 'WPF process did not start'}
    $nativeHandle=$p.Handle
    $observed.pid=$p.Id
    $observed.process_started=$p.StartTime.ToString('o')
    $rootIdentity=@{pid=$p.Id;utc_ticks=$p.StartTime.ToUniversalTime().Ticks;path=$exe;started=$p.StartTime.ToString('o')}
    $stdout=$p.StandardOutput.ReadToEndAsync()
    $stderr=$p.StandardError.ReadToEndAsync()
    $deadline=(Get-Date).AddSeconds(240)
    $nextObservation=Get-Date
    while(!$p.WaitForExit(200)){
        if((Get-Date) -ge $nextObservation){
            $pending=[Collections.Generic.Queue[object]]::new();$pending.Enqueue($rootIdentity)
            while($pending.Count){
                $parent=$pending.Dequeue()
                if(!(Live-Identity $parent)){continue}
                $parentUtc=[DateTime]::new($parent.utc_ticks,[DateTimeKind]::Utc)
                $dmtf=$parentUtc.ToString('yyyyMMddHHmmss.ffffff',[Globalization.CultureInfo]::InvariantCulture)+'+000'
                $filter="ParentProcessId=$($parent.pid) AND CreationDate >= '$dmtf'"
                $children=@(Get-CimInstance Win32_Process -Filter $filter)
                if(!(Live-Identity $parent)){continue}
                foreach($child in $children){
                    if(!$child.CreationDate -or $child.CreationDate.ToUniversalTime() -lt $parentUtc){$rejectedStale++;continue}
                    if(!(Allowed-Image $child.ExecutablePath)){$rejectedUnexpected++;continue}
                    try{
                        $owned=Get-Process -Id $child.ProcessId -ErrorAction Stop
                        if([Math]::Abs(($owned.StartTime.ToUniversalTime()-$child.CreationDate.ToUniversalTime()).TotalMilliseconds) -gt 10 -or !(Allowed-Image $owned.Path)){$rejectedStale++;continue}
                        $identity=@{pid=$owned.Id;started=$owned.StartTime.ToString('o');utc_ticks=$owned.StartTime.ToUniversalTime().Ticks;path=$owned.Path;parent_pid=$parent.pid;parent_started=$parent.started}
                        $identities[($identity.pid.ToString()+'|'+$identity.started)]=$identity
                        $pending.Enqueue($identity)
                    }catch [Microsoft.PowerShell.Commands.ProcessCommandException]{}
                }
            }
            $nextObservation=(Get-Date).AddSeconds(1)
        }
        if((Get-Date) -gt $deadline){$timedOut=$true;$p.Kill($true);$p.WaitForExit(10000)|Out-Null;break}
    }
    $p.WaitForExit()
    $observed.actual_exit=$p.ExitCode
    $observed.timeout=$timedOut
    $observed.process_ended=$p.ExitTime.ToString('o')
    [IO.File]::WriteAllText((Join-Path $EvidenceRoot 'driver.stdout.txt'),$stdout.GetAwaiter().GetResult(),[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $EvidenceRoot 'driver.stderr.txt'),$stderr.GetAwaiter().GetResult(),[Text.UTF8Encoding]::new($false))
    $observed.sentinel_after_sha256=(Get-FileHash -LiteralPath $sentinel).Hash
    $observed.sentinel_unchanged=$observed.sentinel_after_sha256 -eq $observed.sentinel_before_sha256
    $ui=Get-Content -LiteralPath (Join-Path $EvidenceRoot 'ui-run/ui-result.json') -Raw -Encoding UTF8|ConvertFrom-Json
    $observed.ui_result_sha256=(Get-FileHash -LiteralPath (Join-Path $EvidenceRoot 'ui-run/ui-result.json')).Hash
    $observed.independent_reparse_check=$ui.appearance_reparse_read_and_write_refused
    $observed.ui_passed=$ui.passed
    $observed.observed_child_identities=@($identities.Values)
    $observed.identity_gate='Live parent PID+creation+exe checked before and after CIM; WQL child CreationDate >= parent; expected-image allowlist; live child creation matches snapshot within 10ms; only accepted identities traversed or tested for residuals'
    $observed.rejected_stale_candidates=$rejectedStale
    $observed.rejected_unexpected_image_candidates=$rejectedUnexpected
    $grace=(Get-Date).AddSeconds(3)
    do{
        $survivors=@($identities.Values|Where-Object{Live-Identity $_})
        if(!$survivors.Count -or (Get-Date) -ge $grace){break}
        Start-Sleep -Milliseconds 100
    }while($true)
    $observed.observed_identity_survivors=$survivors
    $observed.passed=$p.ExitCode -eq 0 -and !$timedOut -and $ui.passed -and $ui.appearance_reparse_read_and_write_refused -and $observed.sentinel_unchanged -and $survivors.Count -eq 0
}catch{
    $observed.passed=$false
    $observed.observer_error=$_.Exception.Message
    throw
}finally{
    if($observed.pid -and !$p.HasExited){$p.Kill($true);$p.WaitForExit(10000)|Out-Null}
    $observed.observer_ended=(Get-Date).ToString('o')
    $observed|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $outcome -Encoding utf8
    $p.Dispose()
}
if(!$observed.passed){throw 'Independent WPF fixture verification did not pass'}
$observed|ConvertTo-Json -Depth 8
