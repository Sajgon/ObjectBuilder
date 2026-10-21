#requires -Version 7.0
param(
    [Parameter(Mandatory=$true)][string]$FlexSdk,
    [Parameter(Mandatory=$true)][string]$AirSdk,
    [switch]$TestsOnly
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Push-Location $repo
try {
    $flex = (Resolve-Path -LiteralPath $FlexSdk).Path
    $air = (Resolve-Path -LiteralPath $AirSdk).Path
    $frameworks = Join-Path $flex 'frameworks'
    New-Item -ItemType Directory -Path 'workerswfs','bin-release','bin-debug' -Force | Out-Null
    # Apache's binary SDK ships an unresolved AIR placeholder. Keep its relative
    # Flex paths by writing the resolved config alongside the original.
    $configPath = Join-Path $frameworks 'objectbuilder-air-config.xml'
    $config = [IO.File]::ReadAllText((Join-Path $frameworks 'air-config.xml')).Replace('{airHome}', $air.Replace('\','/'))
    [IO.File]::WriteAllText($configPath, $config)
    if ((Get-Item -LiteralPath (Join-Path $air 'frameworks/libs/air/airglobal.swc')).Length -lt 1000) {
        throw 'AIR SDK installation is incomplete.'
    }
    $common = @('-Xmx1536m', "-Dflexlib=$frameworks", '-jar', (Join-Path $flex 'lib\mxmlc.jar'),
        "-load-config=$configPath", '-swf-version=43', '-target-player=32.0',
        '-static-link-runtime-shared-libraries=true', '-source-path=src', '-source-path+=locale/{locale}',
        '-locale=en_US,es_ES,pt_BR', '-library-path+=libs', '-allow-source-path-overlap=true')
    if (!$TestsOnly) {
        & java @common '-debug=false' '-output=workerswfs/ObjectBuilderWorker.swf' 'src/ObjectBuilderWorker.as'
        if ($LASTEXITCODE -ne 0) { throw 'Worker compilation failed.' }
        & java @common '-debug=false' '-output=bin-release/ObjectBuilder.swf' 'src/ObjectBuilder.mxml'
        if ($LASTEXITCODE -ne 0) { throw 'Application compilation failed.' }
        Copy-Item -LiteralPath 'workerswfs/ObjectBuilderWorker.swf' -Destination 'bin-release'
        New-Item -ItemType Directory -Path 'bin-release/icon','bin-release/config' -Force | Out-Null
        Get-ChildItem -LiteralPath 'assets/icon' | Copy-Item -Destination 'bin-release/icon' -Recurse -Force
        Get-ChildItem -LiteralPath 'src/config' | Copy-Item -Destination 'bin-release/config' -Recurse -Force
        $descriptor = [IO.File]::ReadAllText((Join-Path $repo 'src/ObjectBuilder-app.xml'))
        $descriptor = $descriptor.Replace('[This value will be overwritten by Flash Builder in the output app.xml]', 'ObjectBuilder.swf')
        $descriptor = $descriptor.Replace('<versionLabel>0.6.0</versionLabel>', '<versionLabel>0.6.0-savefix.1</versionLabel>')
        [IO.File]::WriteAllText((Join-Path $repo 'bin-release/ObjectBuilder-app.xml'), $descriptor)
    }
    & java @common '-debug=true' '-source-path+=tests' '-output=bin-debug/SaveRegression.swf' 'tests/SaveRegression.as'
    if ($LASTEXITCODE -ne 0) { throw 'Regression test compilation failed.' }
    Copy-Item -LiteralPath 'tests/SaveRegression-app.xml' -Destination 'bin-debug'
    Write-Output 'BUILD SUCCESSFUL'
} finally { Pop-Location }
