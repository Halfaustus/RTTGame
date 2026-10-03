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
    $sessionName = 'RTTGame-local-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
    $logDirectory = Join-Path ([IO.Path]::GetTempPath()) $sessionName
    New-Item -ItemType Directory -Path $logDirectory | Out-Null
    Write-Host "Project: $gamePath"
    Write-Host "Godot: $resolvedGodotPath"
    Write-Host "Server endpoint: 127.0.0.1:$port"
    Write-Host "Logs: $logDirectory"

    # --server is consumed by bootstrap.gd through get_cmdline_user_args().
    $server = Start-TestProcess -Name 'server' -Arguments @('--headless', '--', '--server')
    $startedProcesses += $server
    Wait-TestReady -Instance $server -ReadyPattern ([regex]::Escape("Dedicated server started on port $port."))

    foreach ($clientName in @('client1', 'client2')) {
        $client = Start-TestProcess -Name $clientName -Arguments @()
        $startedProcesses += $client
        Wait-TestReady -Instance $client -ReadyPattern 'Connected to server\. Local peer ID: \d+'
    }
    Write-Host 'Local test ready: one dedicated server and two windowed clients.'
    Write-Host 'Close client windows when finished. Stop only the listed server PID manually.'
    # Return handles for callers that want to inspect their own test session.
    [pscustomobject]@{ LogDirectory = $logDirectory; Instances = $startedProcesses }
}
catch {
    foreach ($instance in $startedProcesses) {
        Write-Host "$($instance.Name): PID $($instance.Process.Id); log: $($instance.LogPath)"
    }
    Write-Error "Local test startup failed: $($_.Exception.Message). Started processes are left running for inspection."
}
