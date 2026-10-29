$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$androidRoot = Join-Path $projectRoot 'android'
$propertiesPath = Join-Path $androidRoot 'key.properties'
$keystorePath = Join-Path $androidRoot 'tranduytan-upload.jks'
if ((Test-Path -LiteralPath $propertiesPath) -or (Test-Path -LiteralPath $keystorePath)) {
    throw 'Signing files already exist. Preserve the key used for installed apps.'
}
$signingBytes = [byte[]]::new(32)
[System.Security.Cryptography.RandomNumberGenerator]::Fill($signingBytes)
$env:TRANDUYTAN_SIGNING_PASSWORD = [Convert]::ToHexString($signingBytes)
$keytoolPath = if ($env:JAVA_HOME -and (Test-Path (Join-Path $env:JAVA_HOME 'bin/keytool.exe'))) {
    Join-Path $env:JAVA_HOME 'bin/keytool.exe'
} else { 'keytool' }
try {
    & $keytoolPath -genkeypair -keystore $keystorePath -storetype JKS -alias upload -keyalg RSA -keysize 3072 -validity 10000 -storepass:env TRANDUYTAN_SIGNING_PASSWORD -keypass:env TRANDUYTAN_SIGNING_PASSWORD -dname 'CN=TRANDUYTAN, OU=Group8, O=TRANDUYTAN, C=VN'
    if ($LASTEXITCODE -ne 0) { throw 'keytool failed' }
    $content = "storePassword=$env:TRANDUYTAN_SIGNING_PASSWORD`nkeyPassword=$env:TRANDUYTAN_SIGNING_PASSWORD`nkeyAlias=upload`nstoreFile=../tranduytan-upload.jks`n"
    [System.IO.File]::WriteAllText($propertiesPath, $content)
    Write-Output 'Signing files created locally. Back up the keystore and key.properties privately.'
} finally {
    Remove-Item Env:TRANDUYTAN_SIGNING_PASSWORD -ErrorAction SilentlyContinue
}
