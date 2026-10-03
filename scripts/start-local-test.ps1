[CmdletBinding()]
param(
    [string]$GodotPath = 'C:\Dev\Godot\Godot.exe',
    [ValidateRange(1, 120)][int]$StartupTimeoutSeconds = 30,
    [switch]$RecordReplay,
    [string]$ReplayOutputPath,
    [ValidateRange(1, 2147483647)][int]$ReplaySnapshotTicks = 300
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$gamePath = Join-Path $projectRoot 'game'
$sessionRoot = Join-Path $projectRoot 'tmp/local-test'
$startedProcesses = @()
$sessionStatus = 'starting'
$sessionError = $null
$sessionId = [Guid]::NewGuid().ToString('N')
$logDirectory = Join-Path $sessionRoot ((Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + $sessionId)
$sessionFile = Join-Path $logDirectory 'session.json'
$resolvedGodotPath = $null
$shutdownRequest = Join-Path $logDirectory 'shutdown-request.json'
$shutdownToken = [Guid]::NewGuid().ToString('N')
$recordingPath = $null

function Write-JsonFile([string]$Path, $Value) {
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
}

function Save-TestSession {
    $records = @($startedProcesses | ForEach-Object { $_.Record })
    Write-JsonFile $sessionFile ([pscustomobject]@{
        Version = 3; SessionId = $sessionId; ProjectPath = $gamePath
        Status = $sessionStatus; Error = $sessionError; Processes = $records
        ShutdownRequest = $shutdownRequest; ShutdownToken = $shutdownToken
        RecordReplay = [bool]$RecordReplay; ReplayOutputPath = $recordingPath; ReplaySnapshotTicks = $ReplaySnapshotTicks
    })
}

function Assert-PortAvailable([int]$Port) {
    # Exclusive wildcard binds detect conflicts without CIM/admin permissions.
    $probes = @()
    try {
        foreach ($family in @([Net.Sockets.AddressFamily]::InterNetwork, [Net.Sockets.AddressFamily]::InterNetworkV6)) {
            if ($family -eq [Net.Sockets.AddressFamily]::InterNetworkV6 -and -not [Net.Sockets.Socket]::OSSupportsIPv6) { continue }
            $probe = [Net.Sockets.Socket]::new($family, [Net.Sockets.SocketType]::Dgram, [Net.Sockets.ProtocolType]::Udp)
            $probes += $probe
            $probe.ExclusiveAddressUse = $true
            if ($family -eq [Net.Sockets.AddressFamily]::InterNetworkV6) { $probe.DualMode = $false }
            $address = if ($family -eq [Net.Sockets.AddressFamily]::InterNetwork) { [Net.IPAddress]::Any } else { [Net.IPAddress]::IPv6Any }
            $probe.Bind([Net.IPEndPoint]::new($address, $Port))
        }
    } catch {
        throw "UDP port $Port is occupied or cannot be bound. No test processes started. $($_.Exception.Message)"
    } finally {
        foreach ($probe in $probes) { $probe.Dispose() }
    }
}

function Start-TestProcess([string]$Name, [string[]]$ExtraArguments) {
    $logPath = Join-Path $logDirectory "$Name.log"
    $arguments = @('--path', $gamePath, '--log-file', $logPath) + $ExtraArguments
    if (@($arguments | Where-Object { $_.Contains('"') }).Count) { throw 'Paths containing double quotes are unsupported.' }
    $argumentString = ($arguments | ForEach-Object { '"' + $_ + '"' }) -join ' '
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $resolvedGodotPath
    $info.Arguments = $argumentString
    $info.WorkingDirectory = $gamePath
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.WindowStyle = if ($Name -eq 'server') { [Diagnostics.ProcessWindowStyle]::Hidden } else { [Diagnostics.ProcessWindowStyle]::Normal }
    # Only these children use project-local user data; parent/system variables are unchanged.
    $info.EnvironmentVariables['APPDATA'] = Join-Path $logDirectory 'appdata'
    $info.EnvironmentVariables['LOCALAPPDATA'] = Join-Path $logDirectory 'localappdata'
    $process = [Diagnostics.Process]::Start($info)
    $instance = [pscustomobject]@{ Name = $Name; Process = $process; LogPath = $logPath; Record = $null }
    $script:startedProcesses += $instance
    $instance.Record = [pscustomobject]@{
        Name = $Name; ProcessId = $process.Id
        StartTimeUtc = $process.StartTime.ToUniversalTime().ToString('o')
        ExecutablePath = $resolvedGodotPath; ProcessName = $process.ProcessName
        Arguments = $argumentString; LogPath = $logPath; SessionId = $sessionId
    }
    Save-TestSession
    Write-Host "$Name started: PID $($process.Id); log: $logPath"
    return $instance
}

function Read-ActiveLog([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    $stream = $null
    $reader = $null
    try {
        $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        $reader = [IO.StreamReader]::new($stream)
        return $reader.ReadToEnd()
    } catch [IO.IOException] { return '' } finally {
        if ($null -ne $reader) { $reader.Dispose() } elseif ($null -ne $stream) { $stream.Dispose() }
    }
}

function Wait-TestReady($Instance, [string]$Marker) {
    $deadline = [DateTime]::UtcNow.AddSeconds($StartupTimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        foreach ($running in $startedProcesses) {
            if ($running.Process.HasExited) { throw "$($running.Name) exited: $($running.Process.ExitCode). Log: $($running.LogPath)" }
            if (Test-Path -LiteralPath $running.LogPath) {
                $content = Read-ActiveLog $running.LogPath
                if ($content -match 'SCRIPT ERROR:|Failed to start server|startup failed|Connection to server failed|Failed to create client connection|Disconnected from server') {
                    throw "$($running.Name) startup/connection failed. Log: $($running.LogPath)"
                }
            }
        }
        if ((Read-ActiveLog $Instance.LogPath).Contains($Marker)) { return }
        Start-Sleep -Milliseconds 100
    }
    throw "$($Instance.Name) timed out after $StartupTimeoutSeconds seconds. Log: $($Instance.LogPath)"
}

try {
    [IO.Directory]::CreateDirectory($logDirectory) | Out-Null
    Save-TestSession
    if (-not (Test-Path -LiteralPath (Join-Path $gamePath 'project.godot'))) { throw "Project missing: $gamePath" }
    $resolvedGodotPath = (Resolve-Path -LiteralPath $GodotPath).Path
    if (-not (Test-Path -LiteralPath $resolvedGodotPath -PathType Leaf)) { throw 'GodotPath must be an executable file.' }
    # Windows console binaries are wrappers. Launch/record the actual engine, not its wrapper PID.
    if ([IO.Path]::GetFileName($resolvedGodotPath) -match '(?i)_console\.exe$') {
        $enginePath = $resolvedGodotPath -replace '(?i)_console\.exe$', '.exe'
        if (-not (Test-Path -LiteralPath $enginePath -PathType Leaf)) { throw "Console wrapper requires matching engine: $enginePath" }
        $resolvedGodotPath = (Resolve-Path -LiteralPath $enginePath).Path
    }
    $networkCode = [IO.File]::ReadAllText((Join-Path $gamePath 'scripts/networking/network_manager.gd'))
    if ($networkCode -notmatch 'const DEFAULT_PORT:\s*int\s*=\s*(\d+)') { throw 'Cannot read production DEFAULT_PORT.' }
    $port = [int]$Matches[1]
    Assert-PortAvailable $port
    if ($ReplayOutputPath -and -not $RecordReplay) { throw 'ReplayOutputPath requires -RecordReplay.' }
    if ($RecordReplay) {
        $recordingPath = if ($ReplayOutputPath) { [IO.Path]::GetFullPath($ReplayOutputPath) } else { Join-Path $logDirectory 'match.rttreplay.json' }
        foreach ($candidate in @($recordingPath, "$recordingPath.incomplete", "$recordingPath.publishing", "$recordingPath.status.json")) {
            if (Test-Path -LiteralPath $candidate) { throw "Replay output/staging exists: $candidate" }
        }
    }
    Write-Host "Logs and session: $logDirectory"
    $serverArguments = @('--headless', '--', '--server', "--shutdown-request=$shutdownRequest", "--shutdown-token=$shutdownToken")
    if ($RecordReplay) { $serverArguments += @("--record-replay=$recordingPath", "--replay-snapshot-ticks=$ReplaySnapshotTicks") }
    $server = Start-TestProcess 'server' $serverArguments
    Wait-TestReady $server "Dedicated server started on port $port."
    if ($RecordReplay) {
        $recordingStatusFile = "$recordingPath.status.json"
        if (-not (Test-Path -LiteralPath $recordingStatusFile) -or ([IO.File]::ReadAllText($recordingStatusFile) | ConvertFrom-Json).status -ne 'recording') {
            throw "Replay recording failed to start. See $($server.LogPath) and $recordingStatusFile"
        }
    }
    foreach ($clientName in @('client-A', 'client-B')) {
        $client = Start-TestProcess $clientName @('--windowed')
        Wait-TestReady $client 'Connected to server. Local peer ID:'
    }
    $sessionStatus = 'ready'
    Save-TestSession
    Write-JsonFile (Join-Path $sessionRoot 'latest-session.json') ([pscustomobject]@{ SessionFile = $sessionFile; SessionId = $sessionId })
    Write-Host 'READY: production server and two windowed clients connected.'
    Write-Host "Stop: powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$PSScriptRoot\stop-local-test.ps1`" -SessionFile `"$sessionFile`""
    [pscustomobject]@{ LogDirectory = $logDirectory; SessionFile = $sessionFile; Instances = $startedProcesses }
} catch {
    $sessionError = $_.Exception.Message
    $cleanupErrors = @()
    foreach ($instance in $startedProcesses) {
        try {
            if (-not $instance.Process.HasExited) {
                $instance.Process.Kill()
                if (-not $instance.Process.WaitForExit(5000)) { throw 'Process did not stop.' }
            }
        } catch { $cleanupErrors += "$($instance.Name): $($_.Exception.Message)" }
    }
    $sessionStatus = if ($cleanupErrors.Count) { 'failed-cleanup-incomplete' } else { 'failed-cleaned' }
    if ($cleanupErrors.Count) { $sessionError += '; cleanup: ' + ($cleanupErrors -join '; ') }
    if (Test-Path -LiteralPath $logDirectory) { Save-TestSession }
    throw "Startup failed: $sessionError. Session/logs retained: $sessionFile"
}
