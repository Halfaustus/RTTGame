[CmdletBinding()]
param([string]$SessionFile)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$expectedProject = Join-Path $projectRoot 'game'
if ([string]::IsNullOrWhiteSpace($SessionFile)) {
    $latestPath = Join-Path $projectRoot 'tmp/local-test/latest-session.json'
    if (-not (Test-Path -LiteralPath $latestPath)) { throw 'No successful local session recorded. Supply -SessionFile.' }
    $SessionFile = ([IO.File]::ReadAllText($latestPath) | ConvertFrom-Json).SessionFile
}
$session = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $SessionFile).Path) | ConvertFrom-Json
if ($session.Version -ne 2 -or [string]::IsNullOrWhiteSpace($session.SessionId)) { throw 'Invalid session manifest.' }
if (-not [string]::Equals([IO.Path]::GetFullPath($session.ProjectPath), [IO.Path]::GetFullPath($expectedProject), [StringComparison]::OrdinalIgnoreCase)) { throw 'Manifest belongs to another project.' }
$records = @($session.Processes)
if ($records.Count -gt 3) { throw 'Invalid process count.' }
# Validate every record before stopping anything.
foreach ($record in $records) {
    if ($null -eq $record -or $record.Name -notin @('server','client-A','client-B') -or $record.SessionId -ne $session.SessionId -or $record.ProcessId -le 0) { throw 'Invalid process identity record.' }
    $null = [DateTime]::Parse($record.StartTimeUtc).ToUniversalTime()
    if ([string]::IsNullOrWhiteSpace($record.ExecutablePath) -or [string]::IsNullOrWhiteSpace($record.ProcessName)) { throw 'Missing executable identity.' }
    if (-not $record.Arguments.Contains($session.ProjectPath) -or -not $record.Arguments.Contains($record.LogPath)) { throw 'Invalid project/log identity.' }
}
$results = @()
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
                $process.Kill()
                if (-not $process.WaitForExit(5000)) { throw 'Timed out waiting for process exit.' }
                $status = 'stopped'
            }
        } catch {
            if ($process.HasExited) { $status = 'already-exited' } else { $status = 'stop-failed'; Write-Warning $_.Exception.Message }
        }
    }
    Write-Host "$($record.Name), PID $($record.ProcessId): $status"
    $results += [pscustomobject]@{ Name = $record.Name; ProcessId = $record.ProcessId; Status = $status }
}
$resultFile = Join-Path (Split-Path -Parent $SessionFile) ('stop-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.json')
[IO.File]::WriteAllText($resultFile, ([pscustomobject]@{ SessionId=$session.SessionId; TimeUtc=[DateTime]::UtcNow.ToString('o'); Results=$results } | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
if (@($results | Where-Object { $_.Status -in @('identity-mismatch-left-running','stop-failed') }).Count) {
    throw "Some processes were left running for safety. Evidence: $resultFile"
}
Write-Host "Session stopped. Logs retained. Evidence: $resultFile"
