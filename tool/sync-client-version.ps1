$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$version = [regex]::Match([IO.File]::ReadAllText((Join-Path $root 'pubspec.yaml')), '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$')
if (!$version.Success) { throw 'Expected semantic version and build in pubspec.yaml.' }
$path = Join-Path $root 'lib/steadylink/client_updates.dart'
$original = [IO.File]::ReadAllText($path)
$updated = [regex]::Replace($original, "const clientVersion = '[^']+';", "const clientVersion = '$($version.Groups[1].Value)';")
$updated = [regex]::Replace($updated, 'const clientBuild = \d+;', "const clientBuild = $($version.Groups[2].Value);")
if ($updated -ne $original) { [IO.File]::WriteAllText($path, $updated, [Text.UTF8Encoding]::new($false)) }
