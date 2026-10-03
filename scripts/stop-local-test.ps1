[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SessionFile
)

$ErrorActionPreference = 'Stop'
$session = Get-Content -LiteralPath $SessionFile -Raw | ConvertFrom-Json
if ($session.Version -ne 1) { throw 'Unsupported session manifest version.' }

foreach ($record in $session.Processes) {
    $process = Get-Process -Id $record.ProcessId -ErrorAction SilentlyContinue
    if (-not $process) {
        Write-Host "$($record.Name): already exited."
        continue
    }
    # PID reuse must never cause an unrelated process to be stopped.
    $expectedStart = [DateTime]::Parse($record.StartTimeUtc).ToUniversalTime()
    if ($process.StartTime.ToUniversalTime().Ticks -ne $expectedStart.Ticks -or
        -not [string]::Equals($process.Path, $record.ExecutablePath, [StringComparison]::OrdinalIgnoreCase)) {
        Write-Warning "$($record.Name): PID $($record.ProcessId) identity differs; left running."
        continue
    }
    try {
        # Stop through this process handle, rather than looking up the PID again.
        $process.Kill()
        $process.WaitForExit()
        Write-Host "Stopped $($record.Name), PID $($record.ProcessId)."
    } catch {
        if (-not $process.HasExited) { throw }
    }
}
