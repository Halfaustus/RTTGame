param([Parameter(Mandatory=$true)][string]$SessionDirectory)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$dir=[IO.Path]::GetFullPath($SessionDirectory)
if(-not $dir.StartsWith((Join-Path $root 'tmp\acceptance-06abc-'),[StringComparison]::OrdinalIgnoreCase)){throw 'Not an acceptance session directory'}
$s=Get-Content -LiteralPath (Join-Path $dir 'session.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$request=[IO.Path]::GetFullPath($s.shutdownRequest)
if((Split-Path $request) -ne $dir){throw 'Invalid shutdown request path'}
@{action='finish';token=$s.shutdownToken} | ConvertTo-Json | Set-Content -LiteralPath $request -Encoding UTF8
for($i=0;$i -lt 40;$i++){
 if(Test-Path -LiteralPath ($request+'.receipt.json')){break}
 Start-Sleep -Milliseconds 250
}
foreach($id in @($s.clientA,$s.clientB)){
 if($id -le 0){continue}
 $p=Get-Process -Id $id -ErrorAction SilentlyContinue
 if($p -and $p.Path -like '*Godot*'){[void]$p.CloseMainWindow()}
}
if(-not(Test-Path -LiteralPath ($request+'.receipt.json'))){throw 'No normal server shutdown receipt; inspect logs, no unrelated process was stopped'}
Get-Content -LiteralPath ($request+'.receipt.json') -Encoding UTF8
