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
#   - Inno Setup instalado (para crear instalador)
#
# NOTA: Build de SOLO FRONTEND. El backend vive en el servidor central
#       (192.168.1.10) y se corre por separado con 'npm start'.
#
# ============================================

param(
    [string]$Version = "",
    [switch]$SkipInstaller = $false,
    [switch]$Clean = $false,
    [string]$DefaultServerName = "SERVER",
    [string]$DefaultServerIp = "192.168.1.10",
    [int]$DefaultServerPort = 3010
)

# Configuración
$ProjectName = "Control_inventario_SMD"
$AppName = "Control inventario SMD"
$Publisher = "MES"
$ProjectRoot = $PSScriptRoot
$BuildDir = "$ProjectRoot\build\windows\x64\runner\Release"
$DistDir = "$ProjectRoot\dist"
$VersionFile = "$ProjectRoot\VERSION.txt"
$InnoSetupScript = "$ProjectRoot\installer\setup.iss"
$InnoSetupCompiler = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"

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
$InstallerPath = "$DistDir\$InstallerName.exe"
$PubspecLockPath = "$ProjectRoot\pubspec.lock"
$PubspecLockHash = $null
if (Test-Path $PubspecLockPath) {
    $PubspecLockHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $PubspecLockPath).Hash
}

Write-Host ""
Write-Info "Configuración de Build:"
Write-Host "  - Versión: $Version"
Write-Host "  - Directorio de salida: $OutputDir"
Write-Host "  - Nombre del instalador: $InstallerName.exe"
Write-Host "  - Servidor por defecto: $DefaultServerName ($DefaultServerIp`:$DefaultServerPort)"
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

# firebase_core descarga el SDK C++ durante la configuración de CMake. Si una
# descarga se interrumpe puede dejar un ZIP de 0 bytes y una carpeta extracted
# vacía; CMake los considera cacheados y después falla en add_subdirectory.
$FirebaseBuildDir = "$ProjectRoot\build\windows\x64"
$FirebaseZip = "$FirebaseBuildDir\firebase_cpp_sdk_windows_12.7.0.zip"
$FirebaseExtractedRoot = "$FirebaseBuildDir\extracted"
$FirebaseVersionHeader =
    "$FirebaseExtractedRoot\firebase_cpp_sdk_windows\include\firebase\version.h"

if ((Test-Path $FirebaseZip) -and (Get-Item $FirebaseZip).Length -eq 0) {
    Write-Warning "Eliminando descarga incompleta de Firebase (ZIP de 0 bytes)..."
    Remove-Item -Force -LiteralPath $FirebaseZip
}
if ((Test-Path $FirebaseExtractedRoot) -and
    -not (Test-Path $FirebaseVersionHeader)) {
    Write-Warning "Eliminando extracción incompleta de Firebase..."
    Remove-Item -Recurse -Force -LiteralPath $FirebaseExtractedRoot
}

# No dejar un instalador anterior con el mismo nombre si esta compilación falla.
if (Test-Path $InstallerPath) {
    Write-Info "Eliminando instalador anterior de la misma versión..."
    Remove-Item -Force -LiteralPath $InstallerPath
}

$BuildSourceDir = $BuildDir
$UsingNativeFallback = $false
$previousCmakePolicyVersionMinimum = $env:CMAKE_POLICY_VERSION_MINIMUM
$env:CMAKE_POLICY_VERSION_MINIMUM = "3.5"
$flutterBuildExitCode = 1
try {
    flutter build windows --release
    $flutterBuildExitCode = $LASTEXITCODE
}
finally {
    if ([string]::IsNullOrWhiteSpace($previousCmakePolicyVersionMinimum)) {
        Remove-Item Env:CMAKE_POLICY_VERSION_MINIMUM -ErrorAction SilentlyContinue
    } else {
        $env:CMAKE_POLICY_VERSION_MINIMUM = $previousCmakePolicyVersionMinimum
    }
}

if ($flutterBuildExitCode -ne 0) {
    Write-Warning "La compilación nativa falló; intentando fallback sin recompilar Firebase..."

    # Cuando dl.google.com está bloqueado, todavía podemos generar el código Dart
    # actualizado y reutilizar un shell nativo anterior si los plugins no cambiaron.
    $FallbackCandidates = Get-ChildItem -LiteralPath $DistDir -Directory -ErrorAction SilentlyContinue |
        Where-Object {
            $_.FullName -ne $OutputDir -and
            (Test-Path (Join-Path $_.FullName "control_inventario_smd.exe")) -and
            (Test-Path (Join-Path $_.FullName "flutter_windows.dll")) -and
            (Test-Path (Join-Path $_.FullName "data\icudtl.dat"))
        } |
        Sort-Object LastWriteTime -Descending

    $FallbackNativeDir = $null
    foreach ($Candidate in $FallbackCandidates) {
        $CandidateHashFile = Join-Path $Candidate.FullName "BUILD_NATIVE_LOCK.sha256"
        $CandidateExe = Join-Path $Candidate.FullName "control_inventario_smd.exe"
        $IsCompatible = $false

        if ($PubspecLockHash -and (Test-Path $CandidateHashFile)) {
            $CandidateHash = (Get-Content -LiteralPath $CandidateHashFile -First 1).Trim()
            $IsCompatible = $CandidateHash -eq $PubspecLockHash
        } elseif (Test-Path $PubspecLockPath) {
            # Compatibilidad con distribuciones creadas antes de guardar el hash.
            $IsCompatible =
                (Get-Item -LiteralPath $PubspecLockPath).LastWriteTimeUtc -le
                (Get-Item -LiteralPath $CandidateExe).LastWriteTimeUtc
        }

        if ($IsCompatible) {
            $FallbackNativeDir = $Candidate.FullName
            break
        }
    }

    if (-not $FallbackNativeDir) {
        Write-Error "Error compilando Flutter y no hay un shell nativo anterior compatible."
        Write-Error "Se requiere acceso a dl.google.com:443 para reconstruir Firebase."
        exit 1
    }

    $FlutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
    if (-not $FlutterCommand) {
        Write-Error "No se pudo localizar Flutter para generar el bundle Dart."
        exit 1
    }

    $FlutterBinDir = Split-Path -Parent $FlutterCommand.Source
    $FlutterRoot = Split-Path -Parent $FlutterBinDir
    $ToolBackend = Join-Path $FlutterRoot "packages\flutter_tools\bin\tool_backend.bat"
    $FlutterEphemeralDir = "$ProjectRoot\windows\flutter\ephemeral"
    $GeneratedConfigFile = Join-Path $FlutterEphemeralDir "generated_config.cmake"
    $DartAppSo = "$ProjectRoot\build\windows\app.so"
    $DartFlutterAssets = "$ProjectRoot\build\flutter_assets"

    if (-not (Test-Path $ToolBackend)) {
        Write-Error "No se encontró tool_backend.bat en el SDK de Flutter."
        exit 1
    }

    Write-Info "Reutilizando shell nativo compatible: $FallbackNativeDir"
    Write-Info "Generando bundle Dart actualizado..."

    $DartEnvironmentNames = @(
        "FLUTTER_ROOT",
        "PROJECT_DIR",
        "FLUTTER_EPHEMERAL_DIR",
        "FLUTTER_TARGET",
        "DART_DEFINES",
        "DART_OBFUSCATION",
        "TRACK_WIDGET_CREATION",
        "TREE_SHAKE_ICONS",
        "PACKAGE_CONFIG"
    )
    $PreviousDartEnvironment = @{}
    foreach ($EnvironmentName in $DartEnvironmentNames) {
        $PreviousDartEnvironment[$EnvironmentName] =
            [Environment]::GetEnvironmentVariable($EnvironmentName, "Process")
    }

    $dartBundleExitCode = 1
    try {
        $env:FLUTTER_ROOT = $FlutterRoot
        $env:PROJECT_DIR = $ProjectRoot
        $env:FLUTTER_EPHEMERAL_DIR = $FlutterEphemeralDir
        $env:FLUTTER_TARGET = "lib\main.dart"
        $env:DART_OBFUSCATION = "false"
        $env:TRACK_WIDGET_CREATION = "true"
        $env:TREE_SHAKE_ICONS = "true"
        $env:PACKAGE_CONFIG = "$ProjectRoot\.dart_tool\package_config.json"

        if (Test-Path $GeneratedConfigFile) {
            $GeneratedConfig = Get-Content -LiteralPath $GeneratedConfigFile
            foreach ($ConfigLine in $GeneratedConfig) {
                if ($ConfigLine -match '"DART_DEFINES=(.*?)"') {
                    $env:DART_DEFINES = $Matches[1]
                    break
                }
            }
        }

        & $ToolBackend windows-x64 Release
        $dartBundleExitCode = $LASTEXITCODE
    }
    finally {
        foreach ($EnvironmentName in $DartEnvironmentNames) {
            [Environment]::SetEnvironmentVariable(
                $EnvironmentName,
                $PreviousDartEnvironment[$EnvironmentName],
                "Process"
            )
        }
    }

    if ($dartBundleExitCode -ne 0 -or
        -not (Test-Path $DartAppSo) -or
        -not (Test-Path $DartFlutterAssets)) {
        Write-Error "No se pudo generar el bundle Dart de respaldo."
        exit 1
    }

    $BuildSourceDir = $FallbackNativeDir
    $UsingNativeFallback = $true
    Write-Success "Bundle Dart generado; se continuará con el shell nativo compatible."
} else {
    Write-Success "Flutter compilado exitosamente"
}

# Paso 2: Crear estructura de distribución (solo frontend)
Write-Host ""
Write-Host "============================================" -ForegroundColor Blue
Write-Info "PASO 2: Creando estructura de distribución (frontend)..."
Write-Host "============================================" -ForegroundColor Blue

# Crear directorio de salida
if (Test-Path $OutputDir) {
    Remove-Item -Recurse -Force $OutputDir
}
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

# Copiar ejecutable Flutter y DLLs (frontend puro, sin backend)
Write-Info "Copiando aplicación Flutter..."
Copy-Item -Recurse "$BuildSourceDir\*" "$OutputDir\"

if ($UsingNativeFallback) {
    $OutputFlutterAssets = "$OutputDir\data\flutter_assets"
    if (Test-Path $OutputFlutterAssets) {
        Remove-Item -Recurse -Force -LiteralPath $OutputFlutterAssets
    }
    New-Item -ItemType Directory -Path $OutputFlutterAssets -Force | Out-Null
    Copy-Item -Recurse -Force "$DartFlutterAssets\*" "$OutputFlutterAssets\"
    Copy-Item -Force -LiteralPath $DartAppSo "$OutputDir\data\app.so"
    Write-Success "Código Dart actualizado integrado en el shell nativo."
}

if ($PubspecLockHash) {
    $PubspecLockHash |
        Out-File -FilePath "$OutputDir\BUILD_NATIVE_LOCK.sha256" -Encoding ASCII -NoNewline
}

# Credenciales opcionales para consultar la carpeta UNC de actualizaciones.
# El archivo real está excluido de Git y se copia solo cuando existe en la
# máquina que genera el instalador; en cada PC queda junto al ejecutable.
$EnvFile = "$ProjectRoot\.env"
$OutputEnvFile = "$OutputDir\.env"
if (Test-Path $OutputEnvFile) {
    Remove-Item -Force -LiteralPath $OutputEnvFile
}
if (Test-Path $EnvFile) {
    Copy-Item -Force $EnvFile $OutputEnvFile
    Write-Info "Copiando configuración de acceso a actualizaciones (.env)..."
} else {
    Write-Warning "No se encontró .env; el instalador requerirá acceso SMB preconfigurado."
}

# Crear archivo de versión
$Version | Out-File -FilePath "$OutputDir\VERSION.txt" -Encoding UTF8 -NoNewline

# Config inicial del servidor central para equipos usuario.
# La app lee este JSON en el primer arranque (ServerConfig._loadInstalledDefaultServer).
$DefaultServerConfig = [ordered]@{
    id = "installed-default"
    name = $DefaultServerName
    ip = $DefaultServerIp
    port = $DefaultServerPort
    useHttps = $false
} | ConvertTo-Json
$DefaultServerConfig | Out-File -FilePath "$OutputDir\default_server_config.json" -Encoding UTF8

# Crear script de inicio (ya no necesita verificar Node.js)
Write-Info "Creando scripts de inicio..."

# Script VBS para USUARIO: solo app Flutter, apunta al servidor central.
# El backend NO corre en las PC de usuario.
@"
Set WshShell = CreateObject("WScript.Shell")
WshShell.CurrentDirectory = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)

' Iniciar la aplicación Flutter conectada al servidor central
WshShell.Run "control_inventario_smd.exe", 1, False
"@ | Out-File -FilePath "$OutputDir\Iniciar.vbs" -Encoding ASCII

# Crear acceso directo al VBS (opcional - el .bat es para debug)
@"
@echo off
cscript //nologo "%~dp0Iniciar.vbs"
"@ | Out-File -FilePath "$OutputDir\Iniciar.bat" -Encoding ASCII

# Script para detener (solo la app; el backend vive en el servidor)
@"
@echo off
taskkill /F /IM control_inventario_smd.exe 2>nul
"@ | Out-File -FilePath "$OutputDir\Detener.bat" -Encoding ASCII

Write-Success "Estructura de distribución creada en: $OutputDir"

# Paso 3: Crear instalador con Inno Setup
if (-not $SkipInstaller) {
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Blue
    Write-Info "PASO 3: Creando instalador..."
    Write-Host "============================================" -ForegroundColor Blue
    
    # Crear directorio para instalador
    $InstallerDir = "$ProjectRoot\installer"
    if (-not (Test-Path $InstallerDir)) {
        New-Item -ItemType Directory -Path $InstallerDir -Force | Out-Null
    }

    # Compilar fuera de OneDrive evita bloqueos transitorios mientras sincroniza
    # el instalador. Después se publica en dist con reintentos.
    $InstallerStagingDir = Join-Path ([System.IO.Path]::GetTempPath()) (
        "Control_inventario_SMD-installer-{0}-{1}" -f
        $PID,
        [Guid]::NewGuid().ToString("N")
    )
    New-Item -ItemType Directory -Path $InstallerStagingDir -Force | Out-Null
    $StagedInstallerPath = Join-Path $InstallerStagingDir "$InstallerName.exe"
    
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
#define OutputDir "$InstallerStagingDir"

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
    $installerCompileExitCode = $LASTEXITCODE
    
    if ($installerCompileExitCode -ne 0 -or -not (Test-Path $StagedInstallerPath)) {
        Write-Error "Error creando instalador"
        if (Test-Path $InstallerStagingDir) {
            Remove-Item -Recurse -Force -LiteralPath $InstallerStagingDir -ErrorAction SilentlyContinue
        }
        exit 1
    }

    Write-Info "Publicando instalador en dist..."
    $InstallerPublished = $false
    $InstallerPublishError = $null
    $InstallerPublishAttempts = 5
    for ($PublishAttempt = 1; $PublishAttempt -le $InstallerPublishAttempts; $PublishAttempt++) {
        try {
            if (Test-Path $InstallerPath) {
                Remove-Item -Force -LiteralPath $InstallerPath -ErrorAction Stop
            }
            Copy-Item -Force -LiteralPath $StagedInstallerPath -Destination $InstallerPath -ErrorAction Stop
            $InstallerPublished = $true
            break
        }
        catch {
            $InstallerPublishError = $_.Exception.Message
            if ($PublishAttempt -lt $InstallerPublishAttempts) {
                Write-Warning (
                    "El instalador está ocupado; reintentando publicación ({0}/{1})..." -f
                    $PublishAttempt,
                    $InstallerPublishAttempts
                )
                Start-Sleep -Seconds 2
            }
        }
    }

    Remove-Item -Recurse -Force -LiteralPath $InstallerStagingDir -ErrorAction SilentlyContinue

    if (-not $InstallerPublished -or -not (Test-Path $InstallerPath)) {
        Write-Error "No se pudo reemplazar el instalador: $InstallerPath"
        Write-Error "Cierre el instalador si está abierto y pause OneDrive temporalmente."
        if ($InstallerPublishError) {
            Write-Error $InstallerPublishError
        }
        exit 1
    }

    Write-Success "Instalador creado: $InstallerPath"
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
Write-Host "Servidor por defecto: $DefaultServerName ($DefaultServerIp`:$DefaultServerPort)" -ForegroundColor White
Write-Host ""
Write-Host "Este build es SOLO FRONTEND (sin backend)." -ForegroundColor Yellow
Write-Host "  - PC usuario: ejecute 'Iniciar.bat' (abre la app, usa el servidor central)" -ForegroundColor Gray
Write-Host "  - Servidor central ($DefaultServerIp): corra el backend con 'npm start' en backend/" -ForegroundColor Gray
Write-Host ""

Set-Location $ProjectRoot
