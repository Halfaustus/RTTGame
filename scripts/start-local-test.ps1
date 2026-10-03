[CmdletBinding()]
param(
    [string]$GodotPath,
    [ValidateRange(1, 120)]
    [int]$StartupTimeoutSeconds = 30
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$gamePath = Join-Path $projectRoot 'game'
$startedProcesses = @()

function Save-TestSession {
    $records = @($startedProcesses | ForEach-Object {
        [pscustomobject]@{
            Name = $_.Name
            ProcessId = $_.Process.Id
            StartTimeUtc = $_.Process.StartTime.ToUniversalTime().ToString('o')
            ExecutablePath = $resolvedGodotPath
            LogPath = $_.LogPath
        }
    })
    [pscustomobject]@{ Version = 1; ProjectPath = $gamePath; Processes = $records } |
        ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $sessionFile -Encoding UTF8
}

function Start-TestProcess {
    param([string]$Name, [string[]]$Arguments)

    $logPath = Join-Path $logDirectory "$Name.log"
    # Godot's own log captures output even when a GUI executable is used.
    $allArguments = @('--path', $gamePath, '--log-file', $logPath) + $Arguments
    $quotedArguments = $allArguments | ForEach-Object { '"' + $_ + '"' }
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $resolvedGodotPath
    $startInfo.Arguments = $quotedArguments -join ' '
    $startInfo.WorkingDirectory = $gamePath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $process = [System.Diagnostics.Process]::Start($startInfo)
    Write-Host "$Name started: PID $($process.Id); log: $logPath"
    return [pscustomobject]@{ Name = $Name; Process = $process; LogPath = $logPath }
}

function Wait-TestReady {
    param($Instance, [string]$ReadyPattern)

    $deadline = [DateTime]::UtcNow.AddSeconds($StartupTimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        foreach ($running in $startedProcesses) {
            if ($running.Process.HasExited) {
                throw "$($running.Name) exited (code $($running.Process.ExitCode)). Log: $($running.LogPath)"
            }
        }
        if (Test-Path -LiteralPath $Instance.LogPath) {
            $content = Get-Content -LiteralPath $Instance.LogPath -Raw
            if ($content -match 'Failed to start server|startup failed|Connection to server failed|Failed to create client connection|Disconnected from server|SCRIPT ERROR:') {
                throw "$($Instance.Name) reported a startup/connection error. Log: $($Instance.LogPath)"
            }
            if ($content -match $ReadyPattern) {
                Write-Host "$($Instance.Name) ready."
                return
            }
        }
        Start-Sleep -Milliseconds 100
    }
    throw "$($Instance.Name) timed out after $StartupTimeoutSeconds seconds. Log: $($Instance.LogPath)"
}

try {
    if (-not (Test-Path -LiteralPath (Join-Path $gamePath 'project.godot'))) {
        throw "Godot project not found: $gamePath"
    }
    if ([string]::IsNullOrWhiteSpace($GodotPath)) {
        foreach ($candidate in @('Godot_console.exe', 'Godot.exe', 'godot')) {
            $command = Get-Command $candidate -CommandType Application -ErrorAction SilentlyContinue
            if ($command) {
                $GodotPath = $command.Source
                break
            }
        }
        if ([string]::IsNullOrWhiteSpace($GodotPath)) {
            throw 'Godot executable not found on PATH. Supply -GodotPath with its full path.'
        }
    }
    $resolvedGodotPath = (Resolve-Path -LiteralPath $GodotPath).Path
    if (-not (Test-Path -LiteralPath $resolvedGodotPath -PathType Leaf)) {
        throw "Godot executable is not a file: $resolvedGodotPath"
    }

    # Read the existing port rather than introducing a launcher port override.
    $networkScript = Get-Content -LiteralPath (Join-Path $gamePath 'scripts/networking/network_manager.gd') -Raw
    if ($networkScript -notmatch 'const DEFAULT_PORT:\s*int\s*=\s*(\d+)') {
        throw 'Cannot determine DEFAULT_PORT from network_manager.gd.'
    }
    $port = [int]$Matches[1]
    # Query all addresses, including wildcard/IPv6 bindings. Fail closed if querying fails.
    $endpoints = @(Get-NetUDPEndpoint -ErrorAction Stop | Where-Object { $_.LocalPort -eq $port })
    if ($endpoints.Count -gt 0) {
        foreach ($endpoint in $endpoints) {
            $ownerProcessId = $endpoint.OwningProcess
            $owner = Get-CimInstance Win32_Process -Filter "ProcessId = $ownerProcessId" -ErrorAction SilentlyContinue
            Write-Host "UDP $($endpoint.LocalAddress):$port occupied: PID $ownerProcessId"
            if ($owner) {
                Write-Host "Name: $($owner.Name); executable: $($owner.ExecutablePath)"
                Write-Host "Command line: $($owner.CommandLine)"
            } else {
                Write-Host 'Process information unavailable (it may have exited or require permission).'
            }
        }
        throw "UDP port $port is already occupied. No test processes were started."
    }
    $sessionName = 'RTTGame-local-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
    $logDirectory = Join-Path ([IO.Path]::GetTempPath()) $sessionName
    New-Item -ItemType Directory -Path $logDirectory | Out-Null
    $sessionFile = Join-Path $logDirectory 'session.json'
    Save-TestSession
    Write-Host "Project: $gamePath"
    Write-Host "Godot: $resolvedGodotPath"
    Write-Host "Server endpoint: 127.0.0.1:$port"
    Write-Host "Logs: $logDirectory"
    Write-Host "Session: $sessionFile"
    $stopScript = Join-Path $PSScriptRoot 'stop-local-test.ps1'
    Write-Host "Stop this session: powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$stopScript`" -SessionFile `"$sessionFile`""

    # --server is consumed by bootstrap.gd through get_cmdline_user_args().
    $server = Start-TestProcess -Name 'server' -Arguments @('--headless', '--', '--server')
    $startedProcesses += $server
    Save-TestSession
    Wait-TestReady -Instance $server -ReadyPattern ([regex]::Escape("Dedicated server started on port $port."))

    foreach ($clientName in @('client1', 'client2')) {
        $client = Start-TestProcess -Name $clientName -Arguments @()
        $startedProcesses += $client
        Save-TestSession
        Wait-TestReady -Instance $client -ReadyPattern 'Connected to server\. Local peer ID: \d+'
    }
    Write-Host 'Local test ready: one dedicated server and two windowed clients.'
    Write-Host 'Use the printed stop command to close only this session.'
    # Return handles for callers that want to inspect their own test session.
    [pscustomobject]@{ LogDirectory = $logDirectory; SessionFile = $sessionFile; Instances = $startedProcesses }
}
catch {
    foreach ($instance in $startedProcesses) {
        Write-Host "$($instance.Name): PID $($instance.Process.Id); log: $($instance.LogPath)"
    }
    Write-Error "Local test startup failed: $($_.Exception.Message). Started processes are left running for inspection."
}
