# Shared by official Android and Windows packaging. Never print config values.
function Get-WristBoxBuildConfig {
  param([string]$ProjectRoot, [string]$ConfigFile = '')
  if (!$ConfigFile) { $ConfigFile = Join-Path $ProjectRoot 'config/production.local.json' }
  $configPath = [IO.Path]::GetFullPath($ConfigFile)
  if (!(Test-Path -LiteralPath $configPath -PathType Leaf)) {
    throw 'Missing local service configuration. Copy config/build.example.json to config/production.local.json and configure your HTTPS service.'
  }
  try { $values = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json }
  catch { throw 'Invalid service configuration JSON.' }
  $allowed = @('WRISTBOX_AUTH_URL', 'WRISTBOX_AUTH_USE_BUNDLED_CA')
  foreach ($name in $values.PSObject.Properties.Name) {
    if ($name -notin $allowed) { throw 'Unsupported build configuration key. Only the service URL and trust-root option are allowed.' }
  }
  $uri = $null
  if ($values.WRISTBOX_AUTH_URL -isnot [string] -or
      ![Uri]::TryCreate($values.WRISTBOX_AUTH_URL, [UriKind]::Absolute, [ref]$uri) -or
      $uri.Scheme -ne 'https' -or !$uri.Host -or $uri.UserInfo -or $uri.Query -or $uri.Fragment -or
      $uri.Host.EndsWith('.invalid') -or $uri.Host -eq 'example.com') {
    throw 'Configure a real HTTPS service URL without credentials, query or fragment; example addresses cannot be used for release packaging.'
  }
  if ($values.WRISTBOX_AUTH_USE_BUNDLED_CA -isnot [bool]) {
    throw 'WRISTBOX_AUTH_USE_BUNDLED_CA must be a JSON boolean.'
  }
  $encoded = foreach ($name in $allowed) {
    $value = $values.$name
    if ($value -is [bool]) { $value = $value.ToString().ToLowerInvariant() }
    [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$name=$value"))
  }
  [pscustomobject]@{ Path = $configPath; DartDefines = ($encoded -join ',') }
}
