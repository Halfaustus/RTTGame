[CmdletBinding()]
param([string]$SessionFile, [ValidateRange(1,60)][int]$TimeoutSeconds=10)

$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($SessionFile)) {
    $latest=Join-Path $projectRoot 'tmp/replay-test/latest-session.json'
    if (-not (Test-Path -LiteralPath $latest)) { throw 'No replay session recorded.' }
    $SessionFile=([IO.File]::ReadAllText($latest) | ConvertFrom-Json).SessionFile
}
$SessionFile=(Resolve-Path -LiteralPath $SessionFile).Path
$session=[IO.File]::ReadAllText($SessionFile) | ConvertFrom-Json
$expectedProject=Join-Path $projectRoot 'game'
$expectedRequest=Join-Path (Split-Path -Parent $SessionFile) 'stop-request.json'
if ($session.Version -ne 1 -or $session.Kind -ne 'offline-replay' -or $session.SessionId -notmatch '^[0-9a-f]{32}$' -or
    $session.StopToken -notmatch '^[0-9a-f]{32}$' -or
    -not [string]::Equals($session.ProjectPath,$expectedProject,[StringComparison]::OrdinalIgnoreCase) -or
    -not [string]::Equals($session.StopRequest,$expectedRequest,[StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid offline replay session identity.' }
$record=$session.Process
if ($null -eq $record -or $record.ProcessId -le 0 -or [string]::IsNullOrWhiteSpace($record.ExecutablePath) -or
    -not $record.Arguments.Contains($expectedProject) -or -not $record.Arguments.Contains($record.LogPath) -or
    -not $record.Arguments.Contains('res://scenes/replay/replay.tscn')) { throw 'Invalid replay process record.' }
$process=Get-Process -Id $record.ProcessId -ErrorAction SilentlyContinue
$status='already-exited'
if ($process) {
    if ($process.StartTime.ToUniversalTime().Ticks -ne [DateTime]::Parse($record.StartTimeUtc).ToUniversalTime().Ticks -or
        -not [string]::Equals($process.Path,$record.ExecutablePath,[StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals($process.ProcessName,$record.ProcessName,[StringComparison]::OrdinalIgnoreCase)) { throw 'Replay PID identity mismatch; process left running.' }
    $null=$process.Handle
    $temporary=$session.StopRequest + '.tmp'
    [IO.File]::WriteAllText($temporary, (@{action='stop_replay';token=$session.StopToken} | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $session.StopRequest -Force
    if (-not $process.WaitForExit($TimeoutSeconds*1000)) { throw 'Replay stop timed out; process left running.' }
    if ($process.ExitCode -ne 0) { throw "Replay exited with error $($process.ExitCode)." }
    $status='stopped'
}
$evidence=Join-Path (Split-Path -Parent $SessionFile) ('stop-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.json')
[IO.File]::WriteAllText($evidence, (@{SessionId=$session.SessionId;ProcessId=$record.ProcessId;Status=$status} | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
Write-Host "Replay $status. Evidence: $evidence"
