; if you want to build this, you need to download and install NSIS from https://nsis.sourceforge.io/Download or
; execute this on a CMD or PowerShell window: winget install NSIS.NSIS

Unicode True

; Installing into the machine wide application data folder and writing the HKLM keys needs admin rights
RequestExecutionLevel admin

!define AUTHOR "YorVeX"

; Automatically detect the name of the parent directory to use it as the app name
!tempfile MYINCFILE
!system 'for %I in (..\.) do echo !define APPNAME "%~nxI" > "${MYINCFILE}"'
!include "${MYINCFILE}"
!delfile "${MYINCFILE}"
!define APPDISPLAYNAME "${APPNAME} OBS Plugin"

; Starting with OBS Studio 33.0, third party plugins are loaded from one shared location
; (https://obsproject.com/kb/legacy-plugin-locations):
;   Module  <ProgramData>\obs-studio\plugins\<name>\<name>.dll
;   Data    <ProgramData>\obs-studio\plugins\<name>\data\*
; Portable installations use the same structure below their own root folder, which is why the release archive ships
; a "plugins" folder that can be extracted into either location. NSIS has no constant for the machine wide
; application data folder, so the path is resolved at runtime into $PLUGIN_DIR (the literal below is only a default).
!define PLUGIN_SUBDIR "obs-studio\plugins\${APPNAME}"

; Automatically detect the version of the library in the publish folder to use it as the app version
!getdllversion "..\publish\win-x64\${APPNAME}.dll" ver
!define VERSION "${ver1}.${ver2}.${ver3}.${ver4}"
!define DISPLAY_VERSION "v${ver1}.${ver2}.${ver3}"
VIProductVersion "${VERSION}"
VIAddVersionKey "ProductName" "${APPNAME}"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "VIProductVersion" "${VERSION}"
VIAddVersionKey "LegalCopyright" "Copyright (c) 2023-2026 ${AUTHOR}, https://github.com/${AUTHOR}"
VIAddVersionKey "FileDescription" "${APPDISPLAYNAME}"

; Main install settings
Name "${APPDISPLAYNAME} ${DISPLAY_VERSION}"
Caption "Async image source plugin for OBS Studio"
Icon "..\img\${APPNAME}-Icon.ico"
UninstallIcon "..\img\${APPNAME}-Icon.ico"
; There is no directory selection page, OBS Studio only loads plugins from the one supported location
InstallDir "C:\ProgramData\${PLUGIN_SUBDIR}"
OutFile "..\release\win-x64\${APPNAME}-${VERSION}-win-x64-installer.exe"
SetCompressor LZMA

; Define splash screen
Function .onInit
	InitPluginsDir
	SetOutPath "$PLUGINSDIR"

	File "/oname=$PLUGINSDIR\Splash.jpg" "..\img\${APPNAME}-SplashScreen.jpg"
	; Need to download and install this plugin for this to work: https://nsis.sourceforge.io/NewAdvSplash_plug-in (the default plugins can only use BMP files)
	newadvsplash::show 1500 500 500 0x04025C /NOCANCEL "$PLUGINSDIR\Splash.jpg"
	Delete "$PLUGINSDIR\Splash.jpg"
FunctionEnd

; Modern interface settings
!include "MUI.nsh"
!include "LogicLib.nsh"
!include "WordFunc.nsh"
!include "WinCore.nsh"
!insertmacro VersionCompare

!define MUI_ABORTWARNING
!define MUI_ICON "..\img\${APPNAME}-Icon.ico"
!define MUI_UNICON "..\img\${APPNAME}-Icon.ico"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "..\LICENSE"
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

; Set languages (first is default language)
!insertmacro MUI_LANGUAGE "English"
!insertmacro MUI_LANGUAGE "French"
!insertmacro MUI_LANGUAGE "German"
!insertmacro MUI_LANGUAGE "Spanish"
!insertmacro MUI_LANGUAGE "Italian"
!insertmacro MUI_LANGUAGE "Dutch"
!insertmacro MUI_LANGUAGE "PortugueseBR"
!insertmacro MUI_RESERVEFILE_LANGDLL

Var PLUGIN_DIR
Var OBS_INSTALL_DIR
Var OBS_VERSION
Var LEGACY_ROOT
Var UNINSTALLER

; Resolves <ProgramData>\obs-studio\plugins\<name> into $PLUGIN_DIR
!macro PLUGIN_DIR_FUNC PREFIX
Function ${PREFIX}ResolvePluginDir
	System::Call 'shell32::SHGetFolderPathW(i 0, i ${CSIDL_COMMON_APPDATA}, i 0, i 0, t .r0)'
	${If} $0 == ""
		StrCpy $0 "C:\ProgramData"
	${EndIf}
	StrCpy $PLUGIN_DIR "$0\${PLUGIN_SUBDIR}"
FunctionEnd
!macroend
!insertmacro PLUGIN_DIR_FUNC ""
!insertmacro PLUGIN_DIR_FUNC "un."

; Finds the OBS Studio installation folder and version, used for the compatibility checks and the legacy cleanup
!macro OBS_DETECT_FUNC PREFIX
Function ${PREFIX}DetectOBS
	StrCpy $OBS_INSTALL_DIR ""
	StrCpy $OBS_VERSION ""

	; OBS Studio is a 64 bit application, but NSIS reads the 32 bit registry view by default
	SetRegView 64
	ReadRegStr $OBS_INSTALL_DIR HKLM "SOFTWARE\OBS Studio" ""
	${If} $OBS_INSTALL_DIR == ""
		ReadRegStr $OBS_INSTALL_DIR HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\OBS Studio" "InstallLocation"
	${EndIf}
	ReadRegStr $OBS_VERSION HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\OBS Studio" "DisplayVersion"
	SetRegView 32
	${If} $OBS_INSTALL_DIR == ""
		ReadRegStr $OBS_INSTALL_DIR HKLM "SOFTWARE\OBS Studio" ""
	${EndIf}
	${If} $OBS_VERSION == ""
		ReadRegStr $OBS_VERSION HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\OBS Studio" "DisplayVersion"
	${EndIf}
	${If} $OBS_INSTALL_DIR == ""
		StrCpy $OBS_INSTALL_DIR "$PROGRAMFILES64\obs-studio"
	${EndIf}
FunctionEnd
!macroend
!insertmacro OBS_DETECT_FUNC ""
!insertmacro OBS_DETECT_FUNC "un."

; Removes files written by older versions of this installer, which used the locations OBS Studio 34.0 stops loading.
; $LEGACY_ROOT is the OBS Studio installation directory to clean up.
!macro OBS_CLEAN_FUNC PREFIX
Function ${PREFIX}CleanLegacyFiles
	${If} $LEGACY_ROOT != ""
	${AndIf} ${FileExists} "$LEGACY_ROOT\*.*"
		; <obs>\obs-plugins\64bit\<name>.dll + <obs>\data\obs-plugins\<name>
		Delete /REBOOTOK "$LEGACY_ROOT\obs-plugins\64bit\${APPNAME}.dll"
		Delete /REBOOTOK "$LEGACY_ROOT\obs-plugins\64bit\${APPNAME}.pdb"
		Delete /REBOOTOK "$LEGACY_ROOT\obs-plugins\uninstall-${APPNAME}-win-x64.exe"
		RMDir /r /REBOOTOK "$LEGACY_ROOT\data\obs-plugins\${APPNAME}"
		; <obs>\plugins\<name>\bin\64bit\<name>.dll
		RMDir /r /REBOOTOK "$LEGACY_ROOT\plugins\${APPNAME}"
	${EndIf}
	; <ProgramData>\obs-studio\plugins\<name>\bin\64bit\<name>.dll
	RMDir /r /REBOOTOK "$PLUGIN_DIR\bin"
FunctionEnd
!macroend
!insertmacro OBS_CLEAN_FUNC ""
!insertmacro OBS_CLEAN_FUNC "un."

Section "${APPDISPLAYNAME}" Section1
	Call ResolvePluginDir
	StrCpy $INSTDIR "$PLUGIN_DIR"
	StrCpy $UNINSTALLER "$INSTDIR\uninstall-${APPNAME}-win-x64.exe"

	Call DetectOBS

	; Nothing is installed into the OBS Studio folder anymore, so a missing installation is only a warning
	${IfNot} ${FileExists} "$OBS_INSTALL_DIR\bin\64bit\obs64.exe"
		MessageBox MB_OKCANCEL|MB_ICONEXCLAMATION "OBS Studio was not found in:$\r$\n$OBS_INSTALL_DIR$\r$\n$\r$\nThe plugin will be installed to the shared OBS Studio plugin folder:$\r$\n$PLUGIN_DIR$\r$\n$\r$\nBut OBS Studio needs to be installed for the plugin to be usable. Install anyway?" IDOK +2
		Abort
	${EndIf}

	${If} $OBS_VERSION != ""
		${VersionCompare} "33.0" "$OBS_VERSION" $R0
		${If} $R0 == 1
			MessageBox MB_OKCANCEL|MB_ICONEXCLAMATION "OBS Studio version $OBS_VERSION was found.$\r$\n$\r$\nThis plugin is installed to the new plugin location introduced in OBS Studio 33.0, so older versions will not load it. Install anyway?" IDOK +2
			Abort
		${EndIf}
	${EndIf}

	; OBS Studio locks the plugin DLL while it runs, so it has to be closed first (silently skipped if the check fails)
	nsExec::ExecToStack 'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "if (Get-Process -Name obs64,obs -ErrorAction SilentlyContinue) { exit 1 }"'
	Pop $R1
	Pop $R2
	${If} $R1 == 1
	${OrIf} $R2 == 1
		MessageBox MB_OK|MB_ICONSTOP "Please close OBS Studio before installing or updating the plugin."
		Abort
	${EndIf}

	; Clean up files of previous installations in the legacy locations
	StrCpy $LEGACY_ROOT "$OBS_INSTALL_DIR"
	Call CleanLegacyFiles
	StrCpy $LEGACY_ROOT "$PROGRAMFILES64\obs-studio"
	Call CleanLegacyFiles

	; Set Section properties
	SetOverwrite on
	AllowSkipFiles off

	; Set Section Files and Shortcuts
	SetOutPath "$INSTDIR"
	File /r "..\publish\win-x64\*.*" ; DLL and PDB file

	SetOutPath "$INSTDIR\data\locale"
	File /r "..\locale\*.*" ; locale files

	CreateDirectory "$SMPROGRAMS\${APPDISPLAYNAME}"
	CreateShortCut "$SMPROGRAMS\${APPDISPLAYNAME}\Uninstall ${APPDISPLAYNAME}.lnk" "$UNINSTALLER"

SectionEnd

Section -FinishSection

	WriteRegStr HKLM "Software\${APPNAME}" "InstallDir" "$INSTDIR"
	WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}" "DisplayName" "${APPDISPLAYNAME}"
	WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}" "UninstallString" "$UNINSTALLER"
	WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}" "Publisher" "${AUTHOR}"
	WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}" "HelpLink" "https://github.com/${AUTHOR}/${APPNAME}"
	WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}" "DisplayVersion" "${DISPLAY_VERSION}"
	WriteUninstaller "$UNINSTALLER"

SectionEnd

; Modern install component descriptions
!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
	!insertmacro MUI_DESCRIPTION_TEXT ${Section1} "Install the ${APPDISPLAYNAME} into the shared OBS Studio plugin folder of this machine"
!insertmacro MUI_FUNCTION_DESCRIPTION_END

UninstallText "This will uninstall the ${APPDISPLAYNAME} from your system"

;Uninstall section
Section Uninstall
	SectionIn RO
	AllowSkipFiles off

	Call un.ResolvePluginDir

	; Installers before the OBS Studio 33.0 plugin location put the uninstaller into the OBS Studio folder
	${IfNot} ${FileExists} "$INSTDIR\*.*"
		StrCpy $INSTDIR "$PLUGIN_DIR"
	${EndIf}
	StrCpy $UNINSTALLER "$INSTDIR\uninstall-${APPNAME}-win-x64.exe"

	;Remove from registry...
	DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}"
	DeleteRegKey HKLM "SOFTWARE\${APPNAME}"

	; Clean up the plugin and data (including locale) files.
	; Only the plugin's own folder is removed recursively, other plugins in the same parent folder stay untouched.
	${If} "$INSTDIR" == "$PLUGIN_DIR"
		RMDir /r /REBOOTOK "$INSTDIR"
	${Else}
		Delete /REBOOTOK "$INSTDIR\${APPNAME}.dll"
		Delete /REBOOTOK "$INSTDIR\${APPNAME}.pdb"
		RMDir /r /REBOOTOK "$INSTDIR\data"
	${EndIf}

	; Clean up files left in the legacy locations
	Call un.DetectOBS
	StrCpy $LEGACY_ROOT "$OBS_INSTALL_DIR"
	Call un.CleanLegacyFiles
	StrCpy $LEGACY_ROOT "$PROGRAMFILES64\obs-studio"
	Call un.CleanLegacyFiles

	; Delete self
	Delete "$UNINSTALLER"
	
	; Delete Shortcuts
	RMDir /r "$SMPROGRAMS\${APPDISPLAYNAME}"

SectionEnd