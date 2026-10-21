#requires -Version 7.0
param(
    [Parameter(Mandatory=$true)][string]$AirSdk,
    [string]$Fixture
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $repo ('bin-debug/save-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$start = [Diagnostics.ProcessStartInfo]::new()
$start.FileName = Join-Path $AirSdk 'bin/adl.exe'
$start.WorkingDirectory = $repo
$start.UseShellExecute = $false
$start.CreateNoWindow = $true
$start.RedirectStandardOutput = $true
$start.RedirectStandardError = $true
$start.ArgumentList.Add((Join-Path $repo 'bin-debug/SaveRegression-app.xml'))
$start.ArgumentList.Add('--')
$start.ArgumentList.Add($testRoot)
if ($Fixture) { $start.ArgumentList.Add((Resolve-Path -LiteralPath $Fixture).Path) }
$proc = [Diagnostics.Process]::Start($start)
$stdout = $proc.StandardOutput.ReadToEndAsync()
$stderr = $proc.StandardError.ReadToEndAsync()
$lock = $null
$deadline = [DateTime]::UtcNow.AddMinutes(5)
try {
    while (!$proc.HasExited) {
        if ([DateTime]::UtcNow -gt $deadline) { throw 'Save regression test timed out.' }
        if (!$lock -and (Test-Path -LiteralPath (Join-Path $testRoot 'LOCK_READY')) -and !(Test-Path -LiteralPath (Join-Path $testRoot 'LOCK_RELEASED'))) {
            # Permit reads for checksum verification, but deny rename/delete.
            $lock = [IO.File]::Open((Join-Path $testRoot 'items.otb'), [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
            [IO.File]::WriteAllText((Join-Path $testRoot 'LOCK_HELD'), 'held')
        }
        if ($lock -and (Test-Path -LiteralPath (Join-Path $testRoot 'LOCK_TESTED'))) {
            $lock.Dispose(); $lock = $null
            [IO.File]::WriteAllText((Join-Path $testRoot 'LOCK_RELEASED'), 'released')
        }
        Start-Sleep -Milliseconds 100
    }
    $proc.WaitForExit()
    $stdout.Result | Set-Content -LiteralPath (Join-Path $testRoot 'stdout.log')
    $stderr.Result | Set-Content -LiteralPath (Join-Path $testRoot 'stderr.log')
    Write-Output "Test output: $testRoot"
    if (Test-Path -LiteralPath (Join-Path $testRoot 'RESULT.txt')) { Get-Content -LiteralPath (Join-Path $testRoot 'RESULT.txt') }
    if ($proc.ExitCode -ne 0) { Write-Output $stdout.Result; Write-Output $stderr.Result; throw "Save regression exited $($proc.ExitCode)" }
    if (!(Test-Path -LiteralPath (Join-Path $testRoot 'RESULT.txt'))) { throw 'Regression test produced no result.' }
} finally {
    if ($lock) { $lock.Dispose() }
    if (!$proc.HasExited) { $proc.Kill(); $proc.WaitForExit() }
    $proc.Dispose()
}
