param([string]$EditorRoot = 'C:\Projects\RTTUnitEditor')
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$outRoot = Join-Path $projectRoot 'tmp\acceptance-06c'
$dataRoot = Join-Path $projectRoot 'game\data\test_only'
New-Item -ItemType Directory -Force $outRoot,$dataRoot | Out-Null
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$sourceRoot = Join-Path $EditorRoot 'src'
$sourceFiles = @(Get-ChildItem -LiteralPath (Join-Path $sourceRoot 'Domain') -Filter '*.cs' | ForEach-Object FullName)
$sourceFiles += @(Get-ChildItem -LiteralPath (Join-Path $sourceRoot 'Storage') -Filter '*.cs' | ForEach-Object FullName)
$sourceFiles += @(Get-ChildItem -LiteralPath (Join-Path $sourceRoot 'Legacy') -Filter '*.cs' | ForEach-Object FullName)
foreach($name in @('EditorSession.cs','AssemblySession.cs','IntegrationBoundaries.cs')) { $sourceFiles += Join-Path $sourceRoot ('Editing\'+$name) }
$sourceFiles += Join-Path $PSScriptRoot 'AcceptanceUnits.cs'
$binary = Join-Path $outRoot 'AcceptanceUnits.exe'
& $compiler /nologo /target:exe /utf8output /codepage:65001 "/out:$binary" /reference:System.dll /reference:System.Core.dll /reference:System.Numerics.dll /reference:System.Web.Extensions.dll @sourceFiles
if($LASTEXITCODE -ne 0){throw 'Compiler failed'}
& $binary (Join-Path $dataRoot 'acceptance_06c.json') (Join-Path $dataRoot 'acceptance_06c_diagnostics.json')
if($LASTEXITCODE -ne 0){throw 'Editor generation failed'}
