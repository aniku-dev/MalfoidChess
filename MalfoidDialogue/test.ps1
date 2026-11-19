$ErrorActionPreference = "Stop"
$projectRoot = $PSScriptRoot

dotnet run --project "$projectRoot\tests\MalfoidDialogue.Tests\MalfoidDialogue.Tests.csproj" --configuration Release
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

