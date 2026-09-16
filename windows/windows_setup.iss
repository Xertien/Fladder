#define SourcePath ".."

#ifndef FLADDER_VERSION
  #define FLADDER_VERSION "latest"
#endif

[Setup]
AppId={{016FFA2A-681C-48EC-8B9D-08D4564641EE}
AppName="Ptaki Cinéma"
AppVersion={#FLADDER_VERSION}
AppPublisher="Xertien"
AppPublisherURL="https://github.com/Xertien/Fladder"
AppSupportURL="https://github.com/Xertien/Fladder"
AppUpdatesURL="https://github.com/Xertien/Fladder"
DefaultDirName={localappdata}\Programs\Ptaki Cinema
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputBaseFilename=ptaki_cinema_setup
Compression=lzma
SolidCompression=yes
WizardStyle=modern

SetupLogging=yes
UninstallLogging=yes
UninstallDisplayName="Ptaki Cinéma"
UninstallDisplayIcon={app}\fladder.exe
SetupIconFile="{#SourcePath}\icons\production\ptaki_icon.ico"
LicenseFile="{#SourcePath}\LICENSE"
WizardImageFile={#SourcePath}\assets\windows-installer\ptaki-installer-100.bmp,{#SourcePath}\assets\windows-installer\ptaki-installer-125.bmp,{#SourcePath}\assets\windows-installer\ptaki-installer-150.bmp

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourcePath}\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Ptaki Cinéma"; Filename: "{app}\fladder.exe"
Name: "{autodesktop}\Ptaki Cinéma"; Filename: "{app}\fladder.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\fladder.exe"; Description: "{cm:LaunchProgram,Ptaki Cinéma}"; Flags: nowait postinstall skipifsilent

[Code]
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  case CurUninstallStep of
    usUninstall:
      begin
        if MsgBox('Would you like to delete the application''s data? This action cannot be undone. Synced files will remain unaffected.', mbConfirmation, MB_YESNO) = IDYES then
        begin
            if DelTree(ExpandConstant('{localappdata}\DonutWare'), True, True, True) = False then
            begin
                Log(ExpandConstant('{localappdata}\DonutWare could not be deleted. Skipping...'));
            end;
        end;
      end;
  end;
end;
