[CmdletBinding()]
param(
    [string]$GodotPath = 'C:\Dev\Godot\Godot_console.exe',
    [ValidateRange(1024, 65535)][int]$TestPort = 17777
)

$ErrorActionPreference = 'Stop'
$rootPath = Split-Path -Parent $PSScriptRoot
$gamePath = Join-Path $rootPath 'game'
$executable = (Resolve-Path -LiteralPath $GodotPath).Path
$processes = @()
$logs = Join-Path ([IO.Path]::GetTempPath()) ('RTTGame-01b-check-' + [Guid]::NewGuid().ToString('N'))

function Start-Role([string]$role) {
    $log = Join-Path $logs "$role.log"
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $executable
    $info.Arguments = "--headless --path `"$gamePath`" --log-file `"$log`" --script res://tests/prototype_01b_test.gd -- --test-role=$role --test-port=$TestPort"
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    [pscustomobject]@{ Role = $role; Log = $log; Process = [Diagnostics.Process]::Start($info) }
}

function Wait-Marker($instance, [string]$marker) {
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (Test-Path -LiteralPath $instance.Log) {
            $text = Get-Content -LiteralPath $instance.Log -Raw
            if ($text -match 'SCRIPT ERROR:|FAIL:|ERROR:') { throw "Test error: $($instance.Log)" }
            if ($text -match [regex]::Escape($marker)) { return }
        }
        if ($instance.Process.HasExited) { throw "Test process exited: $($instance.Log)" }
        Start-Sleep -Milliseconds 100
    }
    throw "Test timeout: $($instance.Log)"
}

try {
    if (@(Get-NetUDPEndpoint -ErrorAction Stop | Where-Object LocalPort -eq $TestPort).Count) {
        throw "Test UDP port $TestPort is occupied; no processes started."
    }
    New-Item -ItemType Directory -Path $logs | Out-Null
    Write-Host "Test logs: $logs"
    $server = Start-Role 'server'; $processes += $server
    Wait-Marker $server "Dedicated server started on port $TestPort."
    $driver = Start-Role 'driver'; $processes += $driver
    Wait-Marker $server 'Authoritative unit 1 created.'
    $observer = Start-Role 'observer'; $processes += $observer
    Wait-Marker $driver 'PASS driver:'
    Wait-Marker $observer 'PASS observer:'
    $late = Start-Role 'late'; $processes += $late
    Wait-Marker $late 'PASS late:'
    foreach ($client in @($driver, $observer, $late)) {
        if (-not $client.Process.WaitForExit(10000) -or $client.Process.ExitCode -ne 0) {
            throw "Client did not finish cleanly: $($client.Log)"
        }
    }
    Wait-Marker $server 'Peer disconnected:'
    $serverText = Get-Content -LiteralPath $server.Log -Raw
    foreach ($reason in @('not owner', 'unknown unit', 'non-finite target', 'target outside prototype bounds', 'target is not on the ground')) {
        if ($serverText -notmatch [regex]::Escape($reason)) { throw "Server did not reject: $reason" }
    }
    Write-Host 'PASS: simulation, right-click request, server validation, two-client replication, late join, selection regression, disconnect.'
}
finally {
    # These handles belong exclusively to this runner; never enumerate/kill Godot globally.
    foreach ($instance in $processes) {
        if (-not $instance.Process.HasExited) { $instance.Process.Kill(); $instance.Process.WaitForExit() }
    }
}
