    # ============================================
# Script de Compilación Automática
# Control de Almacén - MES
# ============================================
# 
# USO: 
#   .\build.ps1                    # Compilar con versión actual
#   .\build.ps1 -Version "1.0.1"   # Compilar con versión específica
#   .\build.ps1 -SkipInstaller     # Solo compilar, sin crear instalador
#
# REQUISITOS:
#   - Flutter SDK instalado y en PATH
#   - Node.js instalado (solo para compilar, no para ejecutar)
#   - Inno Setup instalado (para crear instalador)
#
# NOTA: El backend se compila a .exe, no requiere Node.js en destino
#
# ============================================

param(
    [string]$Version = "",
    [switch]$SkipInstaller = $false,
    [switch]$Clean = $false
)

# Configuración
$ProjectName = "Control_inventario_SMD"
$AppName = "Control inventario SMD"
$Publisher = "MES"
$ProjectRoot = $PSScriptRoot
$BuildDir = "$ProjectRoot\build\windows\x64\runner\Release"
$DistDir = "$ProjectRoot\dist"
$BackendDir = "$ProjectRoot\backend"
$VersionFile = "$ProjectRoot\VERSION.txt"
$InnoSetupScript = "$ProjectRoot\installer\setup.iss"
$InnoSetupCompiler = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
$BackendExeName = "backend-server.exe"

# Colores para output
function Write-Info { param($msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Success { param($msg) Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Warning { param($msg) Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Error { param($msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }

# Banner
Write-Host ""
Write-Host "============================================" -ForegroundColor Magenta
Write-Host "   $AppName - Build System" -ForegroundColor Magenta
Write-Host "============================================" -ForegroundColor Magenta
Write-Host ""

# Obtener versión
if ($Version -eq "") {
    if (Test-Path $VersionFile) {
        $Version = (Get-Content $VersionFile -First 1).Trim()
        Write-Info "Versión detectada desde VERSION.txt: $Version"
    } else {
        $Version = "1.0.0"
        Write-Warning "VERSION.txt no encontrado, usando versión por defecto: $Version"
    }
} else {
    # Actualizar VERSION.txt con la nueva versión
    $Version | Out-File -FilePath $VersionFile -Encoding UTF8 -NoNewline
    Write-Info "VERSION.txt actualizado a: $Version"
}

$BuildVersion = $Version -replace '\.', '_'
$OutputDir = "$DistDir\$ProjectName-v$Version"
$InstallerName = "${ProjectName}_Setup_v${Version}"

Write-Host ""
Write-Info "Configuración de Build:"
Write-Host "  - Versión: $Version"
Write-Host "  - Directorio de salida: $OutputDir"
Write-Host "  - Nombre del instalador: $InstallerName.exe"
Write-Host ""

# Verificar requisitos
Write-Info "Verificando requisitos..."

# Flutter
$flutterVersion = flutter --version 2>&1 | Select-String "Flutter"
if ($LASTEXITCODE -ne 0) {
    Write-Error "Flutter no está instalado o no está en PATH"
    exit 1
}
Write-Success "Flutter: OK"

# Node.js
$nodeVersion = node --version 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "Node.js no está instalado o no está en PATH"
    exit 1
}
Write-Success "Node.js: $nodeVersion"

# Inno Setup (solo si no se salta el instalador)
if (-not $SkipInstaller) {
    if (-not (Test-Path $InnoSetupCompiler)) {
        Write-Warning "Inno Setup no encontrado en: $InnoSetupCompiler"
        Write-Warning "El instalador no se creará. Instale Inno Setup 6 o use -SkipInstaller"
        $SkipInstaller = $true
    } else {
        Write-Success "Inno Setup: OK"
    }
}

Write-Host ""

# Limpiar build anterior si se solicita
if ($Clean) {
    Write-Info "Limpiando build anterior..."
    Set-Location $ProjectRoot
    flutter clean
    if (Test-Path $OutputDir) {
        Remove-Item -Recurse -Force $OutputDir
    }
    Write-Success "Limpieza completada"
}

# Paso 1: Compilar Flutter
Write-Host ""
Write-Host "============================================" -ForegroundColor Blue
Write-Info "PASO 1: Compilando Flutter (Release)..."
Write-Host "============================================" -ForegroundColor Blue

Set-Location $ProjectRoot

# Obtener dependencias
Write-Info "Obteniendo dependencias..."
flutter pub get
if ($LASTEXITCODE -ne 0) {
    Write-Error "Error obteniendo dependencias de Flutter"
    exit 1
}

# Compilar en modo release
Write-Info "Compilando aplicación Windows..."
$previousCmakePolicyVersionMinimum = $env:CMAKE_POLICY_VERSION_MINIMUM
$env:CMAKE_POLICY_VERSION_MINIMUM = "3.5"
try {
    flutter build windows --release
}
finally {
    if ([string]::IsNullOrWhiteSpace($previousCmakePolicyVersionMinimum)) {
        Remove-Item Env:CMAKE_POLICY_VERSION_MINIMUM -ErrorAction SilentlyContinue
    } else {
        $env:CMAKE_POLICY_VERSION_MINIMUM = $previousCmakePolicyVersionMinimum
    }
}
if ($LASTEXITCODE -ne 0) {
    Write-Error "Error compilando Flutter"
    exit 1
}
Write-Success "Flutter compilado exitosamente"

# Paso 2: Compilar Backend a ejecutable
Write-Host ""
Write-Host "============================================" -ForegroundColor Blue
Write-Info "PASO 2: Compilando Backend a ejecutable..."
Write-Host "============================================" -ForegroundColor Blue

Set-Location $BackendDir

# Instalar dependencias incluyendo pkg
Write-Info "Instalando dependencias de Node.js..."
npm install
if ($LASTEXITCODE -ne 0) {
    Write-Error "Error instalando dependencias de Node.js"
    exit 1
}
Write-Success "Dependencias instaladas"

# Verificar/instalar pkg globalmente
Write-Info "Verificando pkg..."
$pkgInstalled = npm list -g pkg 2>&1 | Select-String "pkg@"
if (-not $pkgInstalled) {
    Write-Info "Instalando pkg globalmente..."
    npm install -g pkg
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Error instalando pkg"
        exit 1
    }
}
Write-Success "pkg: OK"

# Crear directorio dist para backend
$BackendDistDir = "$BackendDir\dist"
if (Test-Path $BackendDistDir) {
    Remove-Item -Recurse -Force $BackendDistDir
}
New-Item -ItemType Directory -Path $BackendDistDir -Force | Out-Null

# Compilar servidor a ejecutable
Write-Info "Compilando servidor Node.js a ejecutable..."
pkg . --targets node18-win-x64 --output "$BackendDistDir\$BackendExeName" --compress GZip
if ($LASTEXITCODE -ne 0) {
    Write-Error "Error compilando backend a ejecutable"
    exit 1
}

if (Test-Path "$BackendDistDir\$BackendExeName") {
    $exeSize = (Get-Item "$BackendDistDir\$BackendExeName").Length / 1MB
    Write-Success "Backend compilado exitosamente ($([math]::Round($exeSize, 2)) MB)"
} else {
    Write-Error "No se generó el ejecutable del backend"
    exit 1
}

# Paso 3: Crear estructura de distribución
Write-Host ""
Write-Host "============================================" -ForegroundColor Blue
Write-Info "PASO 3: Creando estructura de distribución..."
Write-Host "============================================" -ForegroundColor Blue

# Crear directorio de salida
if (Test-Path $OutputDir) {
    Remove-Item -Recurse -Force $OutputDir
}
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

# Copiar ejecutable Flutter y DLLs
Write-Info "Copiando aplicación Flutter..."
Copy-Item -Recurse "$BuildDir\*" "$OutputDir\"

# Copiar Backend (solo el ejecutable y configuración)
Write-Info "Copiando Backend compilado..."
Copy-Item "$BackendDir\dist\$BackendExeName" "$OutputDir\"

# Crear archivo .env de ejemplo
Write-Info "Creando archivo de configuración..."
@"
# Configuración de Base de Datos
DB_HOST=localhost
DB_USER=root
DB_PASSWORD=
DB_NAME=meslocal
DB_PORT=3306

# Backend central de solicitudes SMT / FCM
CENTRAL_URL=http://127.0.0.1:4000
"@ | Out-File -FilePath "$OutputDir\.env.example" -Encoding UTF8

# Copiar archivo .env si existe (para desarrollo)
if (Test-Path "$BackendDir\.env") {
    Copy-Item "$BackendDir\.env" "$OutputDir\.env"
}

# Crear archivo de versión
$Version | Out-File -FilePath "$OutputDir\VERSION.txt" -Encoding UTF8 -NoNewline

# Crear script de inicio (ya no necesita verificar Node.js)
Write-Info "Creando scripts de inicio..."

# Script VBS para iniciar sin mostrar consola
@"
Set WshShell = CreateObject("WScript.Shell")
WshShell.CurrentDirectory = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)

' Iniciar Backend en segundo plano (oculto)
WshShell.Run "cmd /c $BackendExeName", 0, False

' Esperar 2 segundos para que inicie el backend
WScript.Sleep 2000

' Iniciar la aplicación Flutter
WshShell.Run "control_inventario_smd.exe", 1, False
"@ | Out-File -FilePath "$OutputDir\Iniciar.vbs" -Encoding ASCII

# Crear acceso directo al VBS (opcional - el .bat es para debug)
@"
@echo off
cscript //nologo "%~dp0Iniciar.vbs"
"@ | Out-File -FilePath "$OutputDir\Iniciar.bat" -Encoding ASCII

# Script para detener
@"
@echo off
echo Deteniendo servicios...
taskkill /F /IM $BackendExeName 2>nul
taskkill /F /IM control_inventario_smd.exe 2>nul
echo Servicios detenidos.
"@ | Out-File -FilePath "$OutputDir\Detener.bat" -Encoding ASCII

Write-Success "Estructura de distribución creada en: $OutputDir"

# Paso 4: Crear instalador con Inno Setup
if (-not $SkipInstaller) {
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Blue
    Write-Info "PASO 4: Creando instalador..."
    Write-Host "============================================" -ForegroundColor Blue
    
    # Crear directorio para instalador
    $InstallerDir = "$ProjectRoot\installer"
    if (-not (Test-Path $InstallerDir)) {
        New-Item -ItemType Directory -Path $InstallerDir -Force | Out-Null
    }
    
    # Generar script de Inno Setup dinámicamente
    Write-Info "Generando script de Inno Setup..."
    
    $InnoScript = @"
; ============================================
; Inno Setup Script - $AppName
; Versión: $Version
; Generado automáticamente por build.ps1
; ============================================

#define MyAppName "$AppName"
#define MyAppVersion "$Version"
#define MyAppPublisher "$Publisher"
#define MyAppExeName "control_inventario_smd.exe"
#define MyAppIcon "$ProjectRoot\logoLogIn.ico"
#define SourceDir "$OutputDir"
#define OutputDir "$DistDir"

[Setup]
AppId={{F3A1D7E9-5B42-4C86-A9F0-7E3B1C8D2A45}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
OutputDir={#OutputDir}
OutputBaseFilename=$InstallerName
SetupIconFile={#MyAppIcon}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\Iniciar.vbs"; IconFilename: "{app}\control_inventario_smd.exe"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\Iniciar.vbs"; IconFilename: "{app}\control_inventario_smd.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\Iniciar.vbs"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent shellexec

[UninstallRun]
Filename: "{app}\Detener.bat"; Flags: runhidden; RunOnceId: "StopControlInventarioSMD"
"@
    
    $InnoScript | Out-File -FilePath $InnoSetupScript -Encoding UTF8
    
    # Compilar instalador
    Write-Info "Compilando instalador..."
    & $InnoSetupCompiler $InnoSetupScript
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Instalador creado: $DistDir\$InstallerName.exe"
    } else {
        Write-Error "Error creando instalador"
    }
}

# Resumen final
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "   BUILD COMPLETADO EXITOSAMENTE" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Versión: $Version" -ForegroundColor White
Write-Host ""
Write-Host "Archivos generados:" -ForegroundColor White
Write-Host "  - Aplicación: $OutputDir" -ForegroundColor Gray
if (-not $SkipInstaller -and (Test-Path "$DistDir\$InstallerName.exe")) {
    Write-Host "  - Instalador: $DistDir\$InstallerName.exe" -ForegroundColor Gray
}
Write-Host ""
Write-Host "Para probar sin instalador:" -ForegroundColor Yellow
Write-Host "  1. Copie la carpeta '$OutputDir' al equipo destino" -ForegroundColor Gray
Write-Host "  2. Configure backend\.env con los datos de la BD" -ForegroundColor Gray
Write-Host "  3. Ejecute 'Iniciar.bat'" -ForegroundColor Gray
Write-Host ""

Set-Location $ProjectRoot
