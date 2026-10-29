param([string] $ApiBaseUrl = '')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ($ApiBaseUrl) {
    $uri = [Uri]$ApiBaseUrl
    if ($uri.Scheme -ne 'https' -or $uri.IsLoopback -or $uri.AbsolutePath -notin '/', '/v1', '/v1/' -or $uri.UserInfo -or $uri.Query -or $uri.Fragment) {
        throw 'Use a public HTTPS API origin or /v1 base URL'
    }
}
if (-not (Test-Path (Join-Path $projectRoot 'android/key.properties'))) {
    & (Join-Path $PSScriptRoot 'init-signing.ps1')
}
Push-Location $projectRoot
try {
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'Dependency installation failed' }
    flutter analyze --no-pub
    if ($LASTEXITCODE -ne 0) { throw 'Flutter analysis failed' }
    flutter test --no-pub
    if ($LASTEXITCODE -ne 0) { throw 'Flutter tests failed' }
    $buildArguments = @('build', 'apk', '--release', '--target', 'lib/main.dart')
    if ($ApiBaseUrl) { $buildArguments += "--dart-define=API_BASE_URL=$ApiBaseUrl" }
    flutter @buildArguments
    if ($LASTEXITCODE -ne 0) { throw 'APK build failed' }
    $outputPath = Join-Path $projectRoot 'output'
    New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
    Copy-Item -LiteralPath 'build/app/outputs/flutter-apk/app-release.apk' -Destination (Join-Path $outputPath 'TRANDUYTAN.apk')
    Get-FileHash -LiteralPath (Join-Path $outputPath 'TRANDUYTAN.apk') -Algorithm SHA256
} finally { Pop-Location }
