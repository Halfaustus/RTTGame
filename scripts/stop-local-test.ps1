[CmdletBinding()]
param([string]$SessionFile, [ValidateRange(1, 300)][int]$ShutdownTimeoutSeconds = 60, [switch]$Force)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$expectedProject = Join-Path $projectRoot 'game'
if ([string]::IsNullOrWhiteSpace($SessionFile)) {
    $latestPath = Join-Path $projectRoot 'tmp/local-test/latest-session.json'
    if (-not (Test-Path -LiteralPath $latestPath)) { throw 'No successful local session recorded. Supply -SessionFile.' }
    $SessionFile = ([IO.File]::ReadAllText($latestPath) | ConvertFrom-Json).SessionFile
}
$session = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $SessionFile).Path) | ConvertFrom-Json
if ($session.Version -notin @(2,3) -or [string]::IsNullOrWhiteSpace($session.SessionId)) { throw 'Invalid session manifest.' }
if (-not [string]::Equals([IO.Path]::GetFullPath($session.ProjectPath), [IO.Path]::GetFullPath($expectedProject), [StringComparison]::OrdinalIgnoreCase)) { throw 'Manifest belongs to another project.' }
$records = @($session.Processes)
if ($session.Version -eq 3) {
    $expectedRequest = Join-Path (Split-Path -Parent ([IO.Path]::GetFullPath($SessionFile))) 'shutdown-request.json'
    if (-not [string]::Equals($expectedRequest, [IO.Path]::GetFullPath($session.ShutdownRequest), [StringComparison]::OrdinalIgnoreCase) -or
        $session.ShutdownToken -notmatch '^[0-9a-f]{32}$') { throw 'Invalid shutdown control identity.' }
}
if ($records.Count -gt 3) { throw 'Invalid process count.' }
# Validate every record before stopping anything.
foreach ($record in $records) {
    if ($null -eq $record -or $record.Name -notin @('server','client-A','client-B') -or $record.SessionId -ne $session.SessionId -or $record.ProcessId -le 0) { throw 'Invalid process identity record.' }
    $null = [DateTime]::Parse($record.StartTimeUtc).ToUniversalTime()
    if ([string]::IsNullOrWhiteSpace($record.ExecutablePath) -or [string]::IsNullOrWhiteSpace($record.ProcessName)) { throw 'Missing executable identity.' }
    if (-not $record.Arguments.Contains($session.ProjectPath) -or -not $record.Arguments.Contains($record.LogPath)) { throw 'Invalid project/log identity.' }
}
$results = @()
function Test-NormalReceipt {
    $receiptPath = $session.ShutdownRequest + '.receipt.json'
    if (-not (Test-Path -LiteralPath $receiptPath)) { return $false }
    $receipt = [IO.File]::ReadAllText($receiptPath) | ConvertFrom-Json
    if (-not $receipt.normal_shutdown -or $receipt.shutdown_token -ne $session.ShutdownToken -or $receipt.exit_code -ne 0) { return $false }
    if ($session.RecordReplay) {
        return $receipt.recording.status -eq 'complete' -and (Test-Path -LiteralPath $session.ReplayOutputPath) -and
            [string]::Equals([IO.Path]::GetFullPath($receipt.recording.output_path), [IO.Path]::GetFullPath($session.ReplayOutputPath), [StringComparison]::OrdinalIgnoreCase)
    }
    return $receipt.recording.status -eq 'disabled'
}
foreach ($record in ($records | Sort-Object @{Expression={ if ($_.Name -eq 'server') { 1 } else { 0 } }})) {
    $process = Get-Process -Id $record.ProcessId -ErrorAction SilentlyContinue
    $status = 'already-exited'
    if ($process) {
        try {
            $expectedStart = [DateTime]::Parse($record.StartTimeUtc).ToUniversalTime()
            if ($process.StartTime.ToUniversalTime().Ticks -ne $expectedStart.Ticks -or
                -not [string]::Equals($process.Path, $record.ExecutablePath, [StringComparison]::OrdinalIgnoreCase) -or
                -not [string]::Equals($process.ProcessName, $record.ProcessName, [StringComparison]::OrdinalIgnoreCase)) {
                $status = 'identity-mismatch-left-running'
                Write-Warning "$($record.Name): PID $($record.ProcessId) identity differs; NOT stopped."
            } else {
                # Keep this verified handle; never resolve the PID again to kill it.
                # Cache the native handle before a voluntary exit so Get-Process
                # can still retrieve the actual exit code on Windows PowerShell.
                $null = $process.Handle
                if ($record.Name -eq 'server' -and $session.Version -eq 3 -and -not $Force) {
                    $requestTemp = $session.ShutdownRequest + '.tmp'
                    [IO.File]::WriteAllText($requestTemp, ([pscustomobject]@{action='finish';token=$session.ShutdownToken} | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
                    Move-Item -LiteralPath $requestTemp -Destination $session.ShutdownRequest -Force
                    if (-not $process.WaitForExit($ShutdownTimeoutSeconds * 1000)) {
                        $status = 'normal-shutdown-timeout-left-running'
                        Write-Warning 'Server did not finish within timeout; left running. Forced termination is not successful finalization.'
                    } else {
                        $status = if ($process.ExitCode -eq 0 -and (Test-NormalReceipt)) { 'normal-stopped' } else { 'recording-finalization-failed' }
                    }
                } else {
                    $process.Kill()
                    if (-not $process.WaitForExit(5000)) { throw 'Timed out waiting for process exit.' }
                    $status = if ($record.Name -eq 'server') { 'forced-stopped-not-finalized' } else { 'stopped' }
                }
            }
        } catch {
            $status = 'stop-failed'
            Write-Warning $_.Exception.Message
        }
    } elseif ($record.Name -eq 'server' -and $session.Version -eq 3) {
        $status = if (Test-NormalReceipt) { 'normal-already-stopped' } else { 'exited-without-successful-finalization' }
    }
    Write-Host "$($record.Name), PID $($record.ProcessId): $status"
    $results += [pscustomobject]@{ Name = $record.Name; ProcessId = $record.ProcessId; Status = $status }
}
$resultFile = Join-Path (Split-Path -Parent $SessionFile) ('stop-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.json')
[IO.File]::WriteAllText($resultFile, ([pscustomobject]@{ SessionId=$session.SessionId; TimeUtc=[DateTime]::UtcNow.ToString('o'); Results=$results } | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
if (@($results | Where-Object { $_.Status -in @('identity-mismatch-left-running','stop-failed','normal-shutdown-timeout-left-running','recording-finalization-failed','forced-stopped-not-finalized','exited-without-successful-finalization') }).Count) {
    throw "Session was not successfully finalized; inspect process/recording status. Evidence: $resultFile"
}
Write-Host "Session stopped. Logs retained. Evidence: $resultFile"
