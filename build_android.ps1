param(
    [string]$Version = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = $PSScriptRoot
$VersionFile = Join-Path $ProjectRoot "VERSION_ANDROID.txt"
$DistDir = Join-Path $ProjectRoot "dist"
$EnvFile = Join-Path $ProjectRoot ".env"

if ([string]::IsNullOrWhiteSpace($Version)) {
    if (-not (Test-Path -LiteralPath $VersionFile)) {
        throw "No se encontró VERSION_ANDROID.txt. Use -Version X.Y.Z."
    }
    $Version = (Get-Content -LiteralPath $VersionFile -First 1).Trim()
}

if ($Version -notmatch '^(\d+)\.(\d+)\.(\d+)$') {
    throw "La versión Android debe usar el formato X.Y.Z."
}

$Major = [int]$Matches[1]
$Minor = [int]$Matches[2]
$Patch = [int]$Matches[3]
$BuildNumber = ($Major * 1000000) + ($Minor * 1000) + $Patch
if ($BuildNumber -le 0 -or $BuildNumber -gt 2100000000) {
    throw "La versión produce un versionCode Android fuera de rango."
}

if (-not (Test-Path -LiteralPath $EnvFile)) {
    throw "No se encontró .env; el APK necesita las credenciales SMB."
}

$Version | Out-File -FilePath $VersionFile -Encoding UTF8 -NoNewline
New-Item -ItemType Directory -Path $DistDir -Force | Out-Null

Set-Location $ProjectRoot
Write-Host "[INFO] Compilando Android v$Version (versionCode $BuildNumber)..." -ForegroundColor Cyan
flutter pub get
if ($LASTEXITCODE -ne 0) {
    throw "Error obteniendo dependencias de Flutter."
}

flutter build apk --release --build-name $Version --build-number $BuildNumber
if ($LASTEXITCODE -ne 0) {
    throw "Error compilando el APK Android."
}

$BuiltApk = Join-Path $ProjectRoot "build\app\outputs\flutter-apk\app-release.apk"
$OutputApk = Join-Path $DistDir "Control_inventario_SMD_v$Version.apk"
Copy-Item -Force -LiteralPath $BuiltApk -Destination $OutputApk

$Hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $OutputApk).Hash
Write-Host "[OK] APK creado: $OutputApk" -ForegroundColor Green
Write-Host "SHA256: $Hash" -ForegroundColor Gray
Write-Host ""
Write-Host "Para publicarlo, copie este archivo a:" -ForegroundColor Yellow
Write-Host "  \\192.168.1.10\updates\SMT\ANDROID" -ForegroundColor Gray
