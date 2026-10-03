[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ReplayFile,
    [string]$GodotPath = 'C:\Dev\Godot\Godot.exe',
    [ValidateRange(0, 9007199254740991)][long]$ViewPlayerId = 0,
    [ValidateRange(1, 120)][int]$StartupTimeoutSeconds = 30,
    [switch]$Headless
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$gamePath = Join-Path $projectRoot 'game'
$sessionRoot = Join-Path $projectRoot 'tmp/replay-test'
$sessionId = [Guid]::NewGuid().ToString('N')
$logDirectory = Join-Path $sessionRoot ((Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + $sessionId)
$sessionFile = Join-Path $logDirectory 'session.json'
$logPath = Join-Path $logDirectory 'replay.log'
$requestPath = Join-Path $logDirectory 'stop-request.json'
$token = [Guid]::NewGuid().ToString('N')
$process = $null
$record = $null
$status = 'starting'
$failure = $null
function Save-ReplaySession {
    [IO.File]::WriteAllText($sessionFile, ([pscustomobject]@{
        Version=1; Kind='offline-replay'; SessionId=$sessionId; ProjectPath=$gamePath
        Status=$status; Error=$failure; Process=$record; StopRequest=$requestPath; StopToken=$token
    } | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
}
function Read-ReplayLog {
    if (-not (Test-Path -LiteralPath $logPath)) { return '' }
    $stream = $null; $reader = $null
    try {
        $stream = [IO.File]::Open($logPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        $reader = [IO.StreamReader]::new($stream)
        return $reader.ReadToEnd()
    } catch [IO.IOException] { return '' } finally {
        if ($reader) { $reader.Dispose() } elseif ($stream) { $stream.Dispose() }
    }
}
try {
    [IO.Directory]::CreateDirectory($logDirectory) | Out-Null
    Save-ReplaySession
    $replayPath = (Resolve-Path -LiteralPath $ReplayFile).Path
    if (-not (Test-Path -LiteralPath $replayPath -PathType Leaf)) { throw 'ReplayFile must be a file.' }
    $enginePath = (Resolve-Path -LiteralPath $GodotPath).Path -replace '(?i)_console\.exe$', '.exe'
    if (-not (Test-Path -LiteralPath $enginePath -PathType Leaf)) { throw 'Godot executable missing.' }
    $mode = if ($Headless) { '--headless' } else { '--windowed' }
    $arguments = @('--path',$gamePath,'--log-file',$logPath,$mode,'res://scenes/replay/replay.tscn','--',
        "--replay-file=$replayPath","--view-player-id=$ViewPlayerId","--replay-stop-request=$requestPath","--replay-stop-token=$token")
    if (@($arguments | Where-Object { $_.Contains('"') }).Count) { throw 'Double quotes in paths are unsupported.' }
    $argumentString = ($arguments | ForEach-Object { '"' + $_ + '"' }) -join ' '
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName=$enginePath; $info.Arguments=$argumentString; $info.WorkingDirectory=$gamePath
    $info.UseShellExecute=$false; $info.CreateNoWindow=$true
    $info.WindowStyle=if ($Headless) { [Diagnostics.ProcessWindowStyle]::Hidden } else { [Diagnostics.ProcessWindowStyle]::Normal }
    $info.EnvironmentVariables['APPDATA'] = Join-Path $logDirectory 'appdata'
    $info.EnvironmentVariables['LOCALAPPDATA'] = Join-Path $logDirectory 'localappdata'
    $process = [Diagnostics.Process]::Start($info)
    $record = [pscustomobject]@{ProcessId=$process.Id;StartTimeUtc=$process.StartTime.ToUniversalTime().ToString('o');ExecutablePath=$enginePath;
        ProcessName=$process.ProcessName;Arguments=$argumentString;LogPath=$logPath;ReplayFile=$replayPath;ViewPlayerId=$ViewPlayerId}
    Save-ReplaySession
    $deadline = [DateTime]::UtcNow.AddSeconds($StartupTimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $content = Read-ReplayLog
        if ($process.HasExited -or $content -match 'REPLAY rejected:|SCRIPT ERROR:') { throw "Replay load failed. Log: $logPath" }
        if ($content.Contains('REPLAY playback ready:')) { $status='ready'; break }
        Start-Sleep -Milliseconds 100
    }
    if ($status -ne 'ready') { throw 'Replay startup timed out.' }
    Save-ReplaySession
    [IO.File]::WriteAllText((Join-Path $sessionRoot 'latest-session.json'), ([pscustomobject]@{SessionFile=$sessionFile} | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    Write-Host "Replay ready: PID $($process.Id); log: $logPath; session: $sessionFile"
    [pscustomobject]@{Process=$process;SessionFile=$sessionFile;LogDirectory=$logDirectory}
} catch {
    $failure=$_.Exception.Message
    if ($process -and -not $process.HasExited) { $process.Kill(); $process.WaitForExit(5000) | Out-Null }
    $status='failed-cleaned'; Save-ReplaySession
    throw "Replay startup failed: $failure. Evidence: $sessionFile"
}
