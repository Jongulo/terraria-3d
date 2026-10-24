; Inno Setup script for the Windows installer. Build it with ..\package.ps1, which stages
; the exported game and the extraction tools in ..\dist\stage and runs ISCC with
;   /DAppVersion=<version> /DStage=<staging folder> /DOutDir=<output folder>
; The installer carries no Terraria assets: it extracts them from the user's own
; Terraria install (extract\extract.ps1) once the files are in place.

#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif
#ifndef Stage
  #define Stage "..\dist\stage"
#endif
#ifndef OutDir
  #define OutDir "..\dist"
#endif

[Setup]
AppId={{6B1F3C2E-8F0A-4C57-9E3B-2D7A4F1C9B60}
AppName=Terraria 3D
AppVersion={#AppVersion}
AppPublisher=Terraria 3D
DefaultDirName={autopf}\Terraria 3D
DefaultGroupName=Terraria 3D
DisableProgramGroupPage=yes
; Per-user (no admin prompt): the game folder stays writable, so "Extract Terraria
; assets" works later without elevation.
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
LicenseFile=..\LICENSE
OutputDir={#OutDir}
OutputBaseFilename=Terraria3D-Setup-{#AppVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\Terraria3D.exe

[Tasks]
Name: desktopicon; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#Stage}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Terraria 3D\Terraria 3D"; Filename: "{app}\Terraria3D.exe"
Name: "{autoprograms}\Terraria 3D\Extract Terraria assets"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\extract\extract.ps1"" -Pause"; \
  Comment: "Extracts the game's art, sounds and music from your Terraria install again"
Name: "{autoprograms}\Terraria 3D\Uninstall Terraria 3D"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Terraria 3D"; Filename: "{app}\Terraria3D.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\Terraria3D.exe"; Description: "{cm:LaunchProgram,Terraria 3D}"; \
  Flags: nowait postinstall skipifsilent; Check: AssetsReady

[UninstallDelete]
; What extraction wrote (the user's worlds and settings, in their AppData, stay).
Type: filesandordirs; Name: "{app}\assets"
Type: files; Name: "{app}\extract\extract.log"
Type: filesandordirs; Name: "{app}\extract\tools\__pycache__"

[Code]
var
  TerrariaPage: TInputDirWizardPage;
  Extracted: Boolean;

function IsTerraria(Dir: String): Boolean;
begin
  Result := (Dir <> '') and FileExists(AddBackslash(Dir) + 'Terraria.exe');
end;

{ Steam libraries (libraryfolders.vdf lists them), then GOG; '' if not found.
  extract.ps1 looks in the same places. }
function FindTerraria(): String;
var
  Steam, Line, P: String;
  Lines: TArrayOfString;
  I, Q: Integer;
begin
  Result := '';
  if not RegQueryStringValue(HKCU, 'Software\Valve\Steam', 'SteamPath', Steam) then
    Steam := ExpandConstant('{commonpf32}\Steam');
  StringChangeEx(Steam, '/', '\', True);
  if IsTerraria(Steam + '\steamapps\common\Terraria') then begin
    Result := Steam + '\steamapps\common\Terraria';
    exit;
  end;
  if LoadStringsFromFile(Steam + '\steamapps\libraryfolders.vdf', Lines) then
    for I := 0 to GetArrayLength(Lines) - 1 do begin
      Line := Trim(Lines[I]);
      if Pos('"path"', Line) = 1 then begin
        P := Trim(Copy(Line, 7, Length(Line)));
        { P is now "D:\\SteamLibrary" with its quotes. }
        Q := Length(P);
        if (Q > 2) and (P[1] = '"') and (P[Q] = '"') then begin
          P := Copy(P, 2, Q - 2);
          StringChangeEx(P, '\\', '\', True);
          if IsTerraria(P + '\steamapps\common\Terraria') then begin
            Result := P + '\steamapps\common\Terraria';
            exit;
          end;
        end;
      end;
    end;
  if RegQueryStringValue(HKLM32, 'SOFTWARE\GOG.com\Games\1207665503', 'path', P) and IsTerraria(P) then
    Result := P
  else if RegQueryStringValue(HKLM64, 'SOFTWARE\GOG.com\Games\1207665503', 'path', P) and IsTerraria(P) then
    Result := P;
end;

procedure InitializeWizard();
begin
  TerrariaPage := CreateInputDirPage(wpSelectDir, 'Your Terraria install',
    'Terraria 3D uses the art, sounds and music of your own copy of Terraria.',
    'Setup will copy them from this folder (the one with Terraria.exe in it). This takes 10 to 15 minutes.' + #13#10#13#10 +
    'If you don''t have Terraria yet, you can install it later and then run "Extract Terraria assets" from the Start menu.',
    False, '');
  TerrariaPage.Add('Terraria folder:');
  TerrariaPage.Values[0] := FindTerraria();
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if (CurPageID = TerrariaPage.ID) and not IsTerraria(TerrariaPage.Values[0]) then
    Result := MsgBox('There''s no Terraria.exe in that folder.' + #13#10#13#10 +
      'Install Terraria 3D anyway? You''ll need to run "Extract Terraria assets" from the Start menu once Terraria is installed.',
      mbConfirmation, MB_YESNO) = IDYES;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  Code: Integer;
begin
  if (CurStep <> ssPostInstall) or not IsTerraria(TerrariaPage.Values[0]) then
    exit;
  WizardForm.StatusLabel.Caption := 'Extracting assets from Terraria (this takes 10 to 15 minutes)...';
  WizardForm.FilenameLabel.Caption := TerrariaPage.Values[0];
  WizardForm.ProgressGauge.Style := npbstMarquee;
  try
    if Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
        '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{app}\extract\extract.ps1') +
        '" -Terraria "' + TerrariaPage.Values[0] + '"',
        ExpandConstant('{app}\extract'), SW_HIDE, ewWaitUntilTerminated, Code) and (Code = 0) then
      Extracted := True
    else
      MsgBox('Extracting the assets from Terraria didn''t work (details: ' +
        ExpandConstant('{app}\extract\extract.log') + ').' + #13#10#13#10 +
        'Terraria 3D is installed; run "Extract Terraria assets" from the Start menu to try again.',
        mbError, MB_OK);
  finally
    WizardForm.ProgressGauge.Style := npbstNormal;
  end;
end;

function AssetsReady(): Boolean;
begin
  Result := Extracted or FileExists(ExpandConstant('{app}\assets\terraria\ids.json'));
end;
