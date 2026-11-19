$ErrorActionPreference = "Stop"
$sourceDirectory = Join-Path $PSScriptRoot "Sources\Chess"
$sourceFiles = @(Get-ChildItem -LiteralPath $sourceDirectory -Filter "*.swift" -File | Sort-Object Name | ForEach-Object FullName)
$engineDirectory = Join-Path $PSScriptRoot "Sources\MalfoidChess"
$engineFiles = @(Get-ChildItem -LiteralPath $engineDirectory -Filter "*.swift" -File | Sort-Object Name | ForEach-Object FullName)
$buildDirectory = Join-Path $PSScriptRoot ".build"
$executable = Join-Path $buildDirectory "MalfoidChess.exe"
$moduleCache = Join-Path $buildDirectory "SwiftModuleCache"
New-Item -ItemType Directory -Force -Path $moduleCache | Out-Null

New-Item -ItemType Directory -Force -Path $buildDirectory | Out-Null
# One frontend compile avoids concurrent module-cache writes in the Windows Swift toolchain.
& swiftc -whole-module-optimization -module-cache-path $moduleCache @sourceFiles @engineFiles -o $executable
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Output "Built $executable"



