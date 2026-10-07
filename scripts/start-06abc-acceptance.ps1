param([string]$Godot='C:\Dev\Godot\Godot_console.exe',[switch]$Full06)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if(-not(Test-Path -LiteralPath $Godot)){throw 'Godot executable unavailable'}
if(Get-NetUDPEndpoint -LocalPort 7777 -ErrorAction SilentlyContinue){throw 'Port 7777 already occupied; existing process was not stopped'}
$dir=Join-Path $root ('tmp\acceptance-06abc-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $dir | Out-Null
$token=[guid]::NewGuid().ToString('N'); $request=Join-Path $dir 'shutdown.json'
$acceptanceFlag=if($Full06){'--acceptance-06'}else{'--acceptance-06c'}
$server=Start-Process -FilePath $Godot -WorkingDirectory $root -ArgumentList @('--headless','--path','game','--','--server',$acceptanceFlag,"--shutdown-request=$request","--shutdown-token=$token") -WindowStyle Hidden -RedirectStandardOutput (Join-Path $dir 'server.log') -RedirectStandardError (Join-Path $dir 'server-error.log') -PassThru
$session=[ordered]@{directory=$dir;server=$server.Id;clientA=0;clientB=0;shutdownRequest=$request;shutdownToken=$token}
$session | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $dir 'session.json') -Encoding UTF8
for($i=0;$i -lt 40;$i++){
 if($server.HasExited){throw ('Server failed; see '+$dir)}
 if((Get-Content -LiteralPath (Join-Path $dir 'server.log') -Raw) -match 'Dedicated server started'){break}
 Start-Sleep -Milliseconds 250
}
if(-not((Get-Content -LiteralPath (Join-Path $dir 'server.log') -Raw) -match 'Dedicated server started')){throw ('Server readiness timeout; see '+$dir)}
$a=Start-Process -FilePath $Godot -WorkingDirectory $root -ArgumentList @('--path','game','--resolution','960x720','--position','40,80','--',$acceptanceFlag) -RedirectStandardOutput (Join-Path $dir 'client-a.log') -RedirectStandardError (Join-Path $dir 'client-a-error.log') -PassThru
$session.clientA=$a.Id
$session | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $dir 'session.json') -Encoding UTF8
Start-Sleep -Milliseconds 1500
$b=Start-Process -FilePath $Godot -WorkingDirectory $root -ArgumentList @('--path','game','--resolution','960x720','--position','1020,80','--',$acceptanceFlag) -RedirectStandardOutput (Join-Path $dir 'client-b.log') -RedirectStandardError (Join-Path $dir 'client-b-error.log') -PassThru
$session.clientB=$b.Id
$session | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $dir 'session.json') -Encoding UTF8
Write-Output ('SESSION='+$dir)
Write-Output ('server='+$server.Id+' clientA='+$a.Id+' clientB='+$b.Id)
