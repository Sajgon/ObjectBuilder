#requires -Version 7.0
param(
    [Parameter(Mandatory=$true)][string]$AirSdk,
    [switch]$Legacy
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $repo ('bin-debug/preview-layout-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$resultFile = Join-Path $testRoot 'RESULT.txt'
$start = [Diagnostics.ProcessStartInfo]::new()
$start.FileName = Join-Path $AirSdk 'bin/adl.exe'
$start.WorkingDirectory = $repo
$start.UseShellExecute = $false
$start.CreateNoWindow = $true
$start.RedirectStandardOutput = $true
$start.RedirectStandardError = $true
$start.ArgumentList.Add((Join-Path $repo 'bin-debug/PreviewLayoutRegression-app.xml'))
$start.ArgumentList.Add('--')
$start.ArgumentList.Add($resultFile)
if ($Legacy) { $start.ArgumentList.Add('--legacy') }
$proc = [Diagnostics.Process]::Start($start)
$stdout = $proc.StandardOutput.ReadToEndAsync()
$stderr = $proc.StandardError.ReadToEndAsync()
try {
    if (!$proc.WaitForExit(60000)) { throw 'Preview layout timed out (UI layout loop).' }
    $stdout.Result | Set-Content -LiteralPath (Join-Path $testRoot 'stdout.log')
    $stderr.Result | Set-Content -LiteralPath (Join-Path $testRoot 'stderr.log')
    Write-Output "Test output: $testRoot"
    if (Test-Path -LiteralPath $resultFile) { Get-Content -LiteralPath $resultFile }
    if ($proc.ExitCode -ne 0 -or !(Test-Path -LiteralPath $resultFile)) { throw "Preview layout regression exited $($proc.ExitCode)." }
} finally {
    if (!$proc.HasExited) { $proc.Kill(); $proc.WaitForExit() }
    $proc.Dispose()
}
