$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'tool/read-build-config.ps1')
$testDir = Join-Path $root 'dist/build-config-tests'
New-Item -ItemType Directory -Path $testDir -Force | Out-Null
$testFile = Join-Path $testDir 'example.local.json'
function Check-Rejected($values) {
  $values | ConvertTo-Json | Set-Content -LiteralPath $testFile -Encoding utf8
  $rejected = $false
  try { Get-WristBoxBuildConfig -ProjectRoot $root -ConfigFile $testFile | Out-Null }
  catch { $rejected = $true }
  if (!$rejected) { throw 'Invalid build configuration was accepted' }
}
$valid = @{WRISTBOX_AUTH_URL='https://store.example.test/service'; WRISTBOX_AUTH_USE_BUNDLED_CA=$true}
$valid | ConvertTo-Json | Set-Content -LiteralPath $testFile -Encoding utf8
$config = Get-WristBoxBuildConfig -ProjectRoot $root -ConfigFile $testFile
$decoded = @($config.DartDefines.Split(',') | ForEach-Object { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_)) })
if ('WRISTBOX_AUTH_URL=https://store.example.test/service' -notin $decoded -or
    'WRISTBOX_AUTH_USE_BUNDLED_CA=true' -notin $decoded) { throw 'Offline defines differ from JSON configuration' }
foreach ($url in @('', 'http://store.example.test/service', 'https://api.example.invalid/service',
    'https://user:password@store.example.test/service', 'https://store.example.test/service?q=1', 'https://store.example.test/service#fragment')) {
  Check-Rejected @{WRISTBOX_AUTH_URL=$url; WRISTBOX_AUTH_USE_BUNDLED_CA=$false}
}
Check-Rejected @{WRISTBOX_AUTH_URL=$valid.WRISTBOX_AUTH_URL; WRISTBOX_AUTH_USE_BUNDLED_CA='true'}
Check-Rejected @{WRISTBOX_AUTH_URL=$valid.WRISTBOX_AUTH_URL; WRISTBOX_AUTH_USE_BUNDLED_CA=$true; SECRET='do-not-inject'}
foreach ($name in @('build-android.ps1','build-windows.ps1','read-build-config.ps1')) {
  $path = Join-Path $root "tool/$name"
  if (!(Test-Path -LiteralPath $path)) { continue }
  $tokens = $null; $errors = $null
  [Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors) | Out-Null
  if ($errors.Count) { throw "PowerShell syntax failed: $name" }
}
'Build config validation, offline encoding and script syntax checks passed.'
