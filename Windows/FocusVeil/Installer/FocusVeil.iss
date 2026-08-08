#ifndef AppVersion
#define AppVersion "0.1.11"
#endif

#ifndef SourceDir
#define SourceDir "..\..\..\outputs\windows"
#endif

#ifndef OutputDir
#define OutputDir "..\..\..\outputs\windows"
#endif

[Setup]
AppId=FocusVeilWindows
AppName=FocusVeil
AppVersion={#AppVersion}
AppPublisher=Steirch
AppPublisherURL=https://github.com/Steirch/FocusVeil
AppSupportURL=https://github.com/Steirch/FocusVeil/issues
AppUpdatesURL=https://github.com/Steirch/FocusVeil/releases
DefaultDirName={localappdata}\Programs\FocusVeil
DefaultGroupName=FocusVeil
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename=FocusVeilSetup
Compression=lzma
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
CloseApplications=yes
RestartApplications=no
UninstallDisplayIcon={app}\FocusVeil.exe

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked
Name: "startup"; Description: "Start FocusVeil when Windows starts"; GroupDescription: "Startup options:"; Flags: unchecked

[Files]
Source: "{#SourceDir}\FocusVeil.exe"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\FocusVeil"; Filename: "{app}\FocusVeil.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\FocusVeil"; Filename: "{app}\FocusVeil.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "FocusVeil"; ValueData: """{app}\FocusVeil.exe"""; Tasks: startup
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: none; ValueName: "FocusVeil"; Flags: dontcreatekey uninsdeletevalue

[Run]
Filename: "{app}\FocusVeil.exe"; Description: "Launch FocusVeil"; Flags: nowait postinstall skipifsilent
