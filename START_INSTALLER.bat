@echo off
setlocal enabledelayedexpansion

:: ============================================================
::  ComfyUI Full Installer - DOUBLE-CLICK THIS FILE
::  Works on Windows 10 and Windows 11
::  Handles: Admin elevation, policy bypass, error logging
:: ============================================================

title ComfyUI Installer
color 0A

:: ── Check if already running as Admin ────────────────────────
net session >nul 2>&1
if %errorlevel% equ 0 goto :IS_ADMIN

:: ── Not admin - re-launch self elevated via PowerShell ───────
echo.
echo  This installer needs Administrator rights.
echo  A Windows security prompt (UAC) will appear.
echo  Click YES to continue.
echo.
echo  Starting in 2 seconds...
timeout /t 2 /nobreak >nul

:: Use quoted path to handle spaces in folder names
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Start-Process -FilePath cmd.exe -ArgumentList '/c ""%~f0""' -Verb RunAs"
exit /b 0

:IS_ADMIN
:: ── Running as Admin ────────────────────────────────────────
cls
color 0B
echo.
echo  ============================================================
echo   ComfyUI Full Auto-Installer  ^|  RTX 3070 Ti Edition
echo   Running as Administrator - Good!
echo  ============================================================
echo.

:: Store the folder this bat file lives in
set "HERE=%~dp0"
if "%HERE:~-1%"=="\" set "HERE=%HERE:~0,-1%"

set "PS1=%HERE%\Install-ComfyUI-Full.ps1"
set "LOG=%USERPROFILE%\Desktop\ComfyUI_Install_Log.txt"

echo  Installer folder : %HERE%
echo  Script file      : %PS1%
echo  Log will save to : %LOG%
echo.

:: ── Check the .ps1 exists ────────────────────────────────────
if not exist "%PS1%" (
    color 0C
    echo.
    echo  ============================================================
    echo   ERROR - Cannot find Install-ComfyUI-Full.ps1
    echo  ============================================================
    echo.
    echo  Both files must be in the same folder:
    echo    START_INSTALLER.bat        ^(this file^)
    echo    Install-ComfyUI-Full.ps1   ^(the main script^)
    echo.
    echo  Files found in current folder:
    dir "%HERE%" /b 2>nul
    echo.
    echo  Press any key to close.
    pause >nul
    exit /b 1
)

:: ── Check PowerShell version ─────────────────────────────────
for /f "tokens=*" %%v in (
    'powershell -NoProfile -Command "$PSVersionTable.PSVersion.Major" 2^>nul'
) do set PS_MAJOR=%%v

if "%PS_MAJOR%"=="" (
    color 0C
    echo  ERROR - Could not detect PowerShell version.
    echo  Please ensure PowerShell 5.1 or later is installed.
    pause >nul
    exit /b 1
)

echo  PowerShell version : %PS_MAJOR%.x detected
echo.
echo  Starting installer in 3 seconds...
echo  Close this window NOW if you want to cancel.
echo.
timeout /t 3 /nobreak >nul

:: ── Run the PowerShell installer ─────────────────────────────
echo  Launching... (a log is being saved to your Desktop)
echo.

powershell -NoProfile -ExecutionPolicy Bypass ^
  -Command "& { $ErrorActionPreference='Continue'; & '%PS1%' } 2>&1 | Tee-Object -FilePath '%LOG%'"

set EXIT_CODE=%errorlevel%

:: ── Show result ───────────────────────────────────────────────
echo.
echo  ============================================================
if %EXIT_CODE% equ 0 (
    color 0A
    echo   DONE! Installation finished successfully.
    echo.
    echo   Check your Desktop for these shortcuts:
    echo     - Launch ComfyUI
    echo     - Launch Kohya_ss Trainer
    echo     - AI Studio Folder
) else (
    color 0C
    echo   Something went wrong  ^(exit code: %EXIT_CODE%^)
    echo.
    echo   Open this file to see what failed:
    echo   %LOG%
    echo.
    echo   Most common fixes:
    echo     1. Check your internet connection
    echo     2. Disable antivirus temporarily
    echo     3. Make sure the chosen drive has 60+ GB free
    echo     4. Run this installer again - it skips finished steps
)
echo  ============================================================
echo.
echo  Press any key to close this window.
pause >nul
exit /b %EXIT_CODE%
