$ErrorActionPreference = "Stop"
$projectRoot = $PSScriptRoot

dotnet build "$projectRoot\src\MalfoidDialogue.Proxy\MalfoidDialogue.Proxy.csproj" --configuration Release
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

dotnet build "$projectRoot\src\MalfoidDialogue.Window\MalfoidDialogue.Window.csproj" --configuration Release
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Build complete. See src\MalfoidDialogue.*\bin\Release."

