; ============================================
; Inno Setup Script - Control inventario SMD
; VersiÃ³n: 1.1.8
; Generado automÃ¡ticamente por build.ps1
; ============================================

#define MyAppName "Control inventario SMD"
#define MyAppVersion "1.1.8"
#define MyAppPublisher "MES"
#define MyAppExeName "control_inventario_smd.exe"
#define MyAppIcon "C:\Users\yahir\OneDrive\Escritorio\MES\Control_inventario_SMD\logoLogIn.ico"
#define SourceDir "C:\Users\yahir\OneDrive\Escritorio\MES\Control_inventario_SMD\dist\Control_inventario_SMD-v1.1.8"
#define OutputDir "C:\Users\yahir\OneDrive\Escritorio\MES\Control_inventario_SMD\dist"

[Setup]
AppId={{F3A1D7E9-5B42-4C86-A9F0-7E3B1C8D2A45}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
OutputDir={#OutputDir}
OutputBaseFilename=Control_inventario_SMD_Setup_v1.1.8
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
