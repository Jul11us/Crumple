Unicode true
!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "WinVer.nsh"
!include "x64.nsh"

!ifndef APP_EXE
  !error "Pass -DAPP_EXE=/absolute/path/Crumple.exe"
!endif
!ifndef OUTPUT_FILE
  !error "Pass -DOUTPUT_FILE=/absolute/path/Crumple-Setup.exe"
!endif
!ifndef NOTICES
  !error "Pass -DNOTICES=/absolute/path/THIRD-PARTY-NOTICES.txt"
!endif
!define VERSION "1.1.1"
!define APPKEY "Software\Crumple"
!define UNINSTALLKEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\Crumple"

Name "Crumple"
OutFile "${OUTPUT_FILE}"
InstallDir "$LOCALAPPDATA\Programs\Crumple"
InstallDirRegKey HKCU "${APPKEY}" "InstallLocation"
RequestExecutionLevel user
SetCompressor /SOLID lzma
BrandingText "Crumple · ${VERSION}"
VIProductVersion "1.1.1.0"
VIAddVersionKey /LANG=1033 "ProductName" "Crumple for Windows"
VIAddVersionKey /LANG=1033 "FileDescription" "Crumple Windows installer (x64)"
VIAddVersionKey /LANG=1033 "ProductVersion" "${VERSION}"
VIAddVersionKey /LANG=1033 "FileVersion" "${VERSION}"
VIAddVersionKey /LANG=1033 "LegalCopyright" "Copyright © 2026 Crumple"

!define MUI_ABORTWARNING
!define MUI_ICON "../Crumple.Desktop/Assets/Crumple.ico"
!define MUI_UNICON "../Crumple.Desktop/Assets/Crumple.ico"
!define MUI_FINISHPAGE_RUN "$INSTDIR\Crumple.exe"
!define MUI_FINISHPAGE_RUN_NOTCHECKED
!define MUI_LANGDLL_REGISTRY_ROOT "HKCU"
!define MUI_LANGDLL_REGISTRY_KEY "${APPKEY}"
!define MUI_LANGDLL_REGISTRY_VALUENAME "InstallerLanguage"
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"
!insertmacro MUI_LANGUAGE "SimpChinese"

!macro RequireCompatibleWindows
  ${IfNot} ${AtLeastWin10}
    MessageBox MB_OK|MB_ICONSTOP "Crumple requires Windows 10 or Windows 11. / 需要 Windows 10 或 Windows 11。"
    Abort
  ${EndIf}
  ${IfNot} ${RunningX64}
    MessageBox MB_OK|MB_ICONSTOP "Crumple requires 64-bit Windows. / 需要 64 位 Windows。"
    Abort
  ${EndIf}
!macroend

!macro RequireAppClosed
  ReadEnvStr $0 "USERNAME"
  System::Call 'kernel32::OpenMutexW(i 0x100000, i 0, w "Local\Crumple.Windows.$0") p.r1'
  ${If} $1 != 0
    System::Call 'kernel32::CloseHandle(p r1)'
    MessageBox MB_OK|MB_ICONEXCLAMATION "Please close Crumple first, including the system tray. / 请先退出 Crumple（包括系统托盘）。"
    Abort
  ${EndIf}
!macroend

Function .onInit
  !insertmacro RequireCompatibleWindows
  !insertmacro RequireAppClosed
  !insertmacro MUI_LANGDLL_DISPLAY
  SetShellVarContext current
FunctionEnd

Section "Crumple" Main
  SetShellVarContext current
  SetOutPath "$INSTDIR"
  File /oname=Crumple.exe "${APP_EXE}"
  File /oname=THIRD-PARTY-NOTICES.txt "${NOTICES}"
  File /oname=README.txt "README.txt"
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  CreateDirectory "$SMPROGRAMS\Crumple"
  CreateShortcut "$SMPROGRAMS\Crumple\Crumple.lnk" "$INSTDIR\Crumple.exe"
  WriteRegStr HKCU "${APPKEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINSTALLKEY}" "DisplayName" "Crumple for Windows"
  WriteRegStr HKCU "${UNINSTALLKEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "${UNINSTALLKEY}" "Publisher" "Crumple"
  WriteRegStr HKCU "${UNINSTALLKEY}" "DisplayIcon" "$INSTDIR\Crumple.exe"
  WriteRegStr HKCU "${UNINSTALLKEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINSTALLKEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKCU "${UNINSTALLKEY}" "QuietUninstallString" '"$INSTDIR\Uninstall.exe" /S'
  WriteRegDWORD HKCU "${UNINSTALLKEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINSTALLKEY}" "NoRepair" 1
SectionEnd

Function un.onInit
  !insertmacro RequireAppClosed
  !insertmacro MUI_UNGETLANGUAGE
  SetShellVarContext current
FunctionEnd

Section "Uninstall"
  SetShellVarContext current
  Delete "$SMPROGRAMS\Crumple\Crumple.lnk"
  RMDir "$SMPROGRAMS\Crumple"
  Delete "$INSTDIR\Crumple.exe"
  Delete "$INSTDIR\THIRD-PARTY-NOTICES.txt"
  Delete "$INSTDIR\README.txt"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
  DeleteRegKey HKCU "${UNINSTALLKEY}"
  DeleteRegKey HKCU "${APPKEY}"
  ; Keep history and settings. Never remove user data or the user's Recycle Bin.
SectionEnd
