param(
  [string]$Flutter = 'flutter',
  [string]$AndroidSdk = '',
  [string]$ConfigFile = '',
  [switch]$SkipTests,
  [switch]$Offline
)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$previousAndroidHome = $env:ANDROID_HOME
$previousAndroidRoot = $env:ANDROID_SDK_ROOT
if ($AndroidSdk) {
  $env:ANDROID_HOME = [IO.Path]::GetFullPath($AndroidSdk)
  $env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
}
Push-Location $projectRoot
try {
  . (Join-Path $PSScriptRoot 'read-build-config.ps1')
  $serviceConfig = Get-WristBoxBuildConfig -ProjectRoot $projectRoot -ConfigFile $ConfigFile
  & (Join-Path $PSScriptRoot 'sync-client-version.ps1')
  if (!(Test-Path -LiteralPath 'android/key.properties')) {
    throw 'Configure android/key.properties with your release signing key before building. Do not commit signing credentials.'
  }
  if ($Offline) { & $Flutter pub get --offline } else { & $Flutter pub get }
  if ($LASTEXITCODE -ne 0) { throw 'Dependency resolution failed.' }
  if (!$SkipTests) {
    & $Flutter analyze --no-pub lib/steadylink lib/main.dart test/steadylink
    if ($LASTEXITCODE -ne 0) { throw 'Analysis failed.' }
    & $Flutter test --no-pub test/steadylink test/features/accounts/services/mi_account_service_test.dart test/features/devices/controllers/device_manager_connection_test.dart test/device/xiaomi/xiaomi_mass_packet_test.dart test/device/xiaomi/xiaomi_spp_v1_packet_test.dart
    if ($LASTEXITCODE -ne 0) { throw 'Tests failed.' }
  }
  $versionLine = Select-String -LiteralPath 'pubspec.yaml' -Pattern '^version:\s*(\S+)'
  $versionParts = $versionLine.Matches[0].Groups[1].Value.Split('+')
  $packageVersion = $versionParts[0]
  # Keep deobfuscation symbols private so production crashes remain diagnosable.
  $symbols = Join-Path $projectRoot "dist/private-symbols/android-$packageVersion-$($versionParts[1])"
  New-Item -ItemType Directory -Path $symbols -Force | Out-Null
  if ($Offline) {
    # Flutter must have configured this checkout at least once. Avoid lint's
    # optional online SDK-index lookup when all build dependencies are cached.
    $propertiesPath = Join-Path $projectRoot 'android/local.properties'
    if (!(Test-Path -LiteralPath $propertiesPath)) { throw 'Run a normal Android build once to configure local.properties.' }
    $properties = [IO.File]::ReadAllText($propertiesPath)
    $properties = [regex]::Replace($properties, '(?m)^flutter.versionName=.*$', "flutter.versionName=$packageVersion")
    $properties = [regex]::Replace($properties, '(?m)^flutter.versionCode=.*$', "flutter.versionCode=$($versionParts[1])")
    [IO.File]::WriteAllText($propertiesPath, $properties, [Text.UTF8Encoding]::new($false))
    Push-Location 'android'
    try {
      & ./gradlew.bat :app:assembleRelease --offline --console=plain '-Ptarget-platform=android-arm,android-arm64,android-x64' '-Ptarget=lib/main_android.dart' '-Pbuild-mode=release' '-Pdart-obfuscation=true' "-Psplit-debug-info=$symbols" "-Pdart-defines=$($serviceConfig.DartDefines)"
      if ($LASTEXITCODE -ne 0) { throw 'Android offline build failed.' }
    } finally { Pop-Location }
    $apk = 'build/app/outputs/apk/release/app-release.apk'
  } else {
    & $Flutter build apk --release --no-pub --obfuscate "--split-debug-info=$symbols" --target lib/main_android.dart "--dart-define-from-file=$($serviceConfig.Path)"
    if ($LASTEXITCODE -ne 0) { throw 'Android build failed.' }
    $apk = 'build/app/outputs/flutter-apk/app-release.apk'
  }
  New-Item -ItemType Directory -Path 'dist' -Force | Out-Null
  $destination = "dist/WristBox-$packageVersion-android.apk"
  Copy-Item -LiteralPath $apk -Destination $destination -Force
  $hash = Get-FileHash -LiteralPath $destination -Algorithm SHA256
  $hash.Hash | Set-Content -LiteralPath "$destination.sha256" -Encoding ascii
  $hash
} finally {
  Pop-Location
  $env:ANDROID_HOME = $previousAndroidHome
  $env:ANDROID_SDK_ROOT = $previousAndroidRoot
}
