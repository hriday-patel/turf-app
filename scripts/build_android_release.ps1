param(
  [string]$SupabaseUrl,
  [string]$SupabaseAnonKey,
  [string]$StorageBucket = "",
  [string]$ApiBaseUrl = ""
)

$ErrorActionPreference = "Stop"

function Get-EnvFileValue {
  param(
    [string]$Path,
    [string]$Key
  )

  if (!(Test-Path $Path)) {
    return ""
  }

  foreach ($rawLine in Get-Content -Path $Path) {
    $line = $rawLine.Trim()
    if ($line.Length -eq 0 -or $line.StartsWith("#")) {
      continue
    }

    $parts = $line.Split("=", 2)
    if ($parts.Length -ne 2) {
      continue
    }

    if ($parts[0].Trim() -eq $Key) {
      $value = $parts[1].Trim()
      if ($value.Length -ge 2 -and (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'")))) {
        $value = $value.Substring(1, $value.Length - 2)
      }
      return $value.Trim()
    }
  }

  return ""
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$envFilePath = Join-Path $projectRoot ".env"

if ([string]::IsNullOrWhiteSpace($SupabaseUrl)) {
  $SupabaseUrl = Get-EnvFileValue -Path $envFilePath -Key "SUPABASE_URL"
}
if ([string]::IsNullOrWhiteSpace($SupabaseAnonKey)) {
  $SupabaseAnonKey = Get-EnvFileValue -Path $envFilePath -Key "SUPABASE_ANON_KEY"
}
if ([string]::IsNullOrWhiteSpace($StorageBucket)) {
  $StorageBucket = Get-EnvFileValue -Path $envFilePath -Key "STORAGE_BUCKET"
}
if ([string]::IsNullOrWhiteSpace($ApiBaseUrl)) {
  $ApiBaseUrl = Get-EnvFileValue -Path $envFilePath -Key "API_BASE_URL"
}
if ([string]::IsNullOrWhiteSpace($ApiBaseUrl)) {
  $ApiBaseUrl = "https://fieldpass-business.vercel.app/api"
}

$ApiBaseUrl = $ApiBaseUrl.Trim()
if ($ApiBaseUrl.EndsWith("/")) {
  $ApiBaseUrl = $ApiBaseUrl.TrimEnd("/")
}

if ([string]::IsNullOrWhiteSpace($SupabaseUrl) -or [string]::IsNullOrWhiteSpace($SupabaseAnonKey)) {
  throw "Missing SUPABASE_URL/SUPABASE_ANON_KEY. Provide params or create .env with those keys before building."
}

$defines = @{
  SUPABASE_URL = $SupabaseUrl
  SUPABASE_ANON_KEY = $SupabaseAnonKey
  API_BASE_URL = $ApiBaseUrl
}

if (![string]::IsNullOrWhiteSpace($StorageBucket)) {
  $defines["STORAGE_BUCKET"] = $StorageBucket
}

$definesPath = Join-Path $projectRoot "dart_defines.local.json"
$definesJson = $defines | ConvertTo-Json
Set-Content -Path $definesPath -Value $definesJson -Encoding UTF8

$flutterShortPath = "C:\Users\HRIDAY~1\OneDrive\Desktop\flutter\bin\flutter.bat"
$flutterCmd = if (Test-Path $flutterShortPath) { $flutterShortPath } else { "flutter" }

$pubCache = "C:\PubCache"
if (!(Test-Path $pubCache)) {
  New-Item -ItemType Directory -Path $pubCache | Out-Null
}

Set-Location $projectRoot

$driveLetter = "X:"
subst $driveLetter $projectRoot

try {
  Set-Location "$driveLetter\"
  $env:PUB_CACHE = $pubCache

  & $flutterCmd clean
  if ($LASTEXITCODE -ne 0) {
    throw "flutter clean failed"
  }

  & $flutterCmd pub get
  if ($LASTEXITCODE -ne 0) {
    Write-Warning "flutter pub get failed (often due to Windows symlink checks). Continuing to build appbundle directly."
  }

  & $flutterCmd build appbundle --release --dart-define-from-file=dart_defines.local.json
  if ($LASTEXITCODE -ne 0) {
    throw "flutter build appbundle failed"
  }

  Write-Host "Release bundle generated at: build/app/outputs/bundle/release/app-release.aab"
}
finally {
  Set-Location $projectRoot
  subst $driveLetter /d | Out-Null
}
