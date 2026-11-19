$ErrorActionPreference = "Stop"
$sourceDirectory = Join-Path $PSScriptRoot "Sources\Chess"
$sourceFiles = @(Get-ChildItem -LiteralPath $sourceDirectory -Filter "*.swift" -File | Sort-Object Name | ForEach-Object FullName)
$testFile = Join-Path $PSScriptRoot "Tests\TestMain.swift"
$buildDirectory = Join-Path $PSScriptRoot ".build"
$testExecutable = Join-Path $buildDirectory "MalfoidChessTests.exe"
$moduleCache = Join-Path $buildDirectory "SwiftModuleCache"
New-Item -ItemType Directory -Force -Path $moduleCache | Out-Null

New-Item -ItemType Directory -Force -Path $buildDirectory | Out-Null
& swiftc -whole-module-optimization -module-cache-path $moduleCache @sourceFiles $testFile -o $testExecutable
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $testExecutable
exit $LASTEXITCODE


