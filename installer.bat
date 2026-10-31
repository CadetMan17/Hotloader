@echo off
setlocal EnableDelayedExpansion
title Hotloader Installer

rem ------------------------------------------------------------
rem  Hotloader installer (Windows)
rem  Run this from the Hotloader repo folder (next to addon.json).
rem  Usage:  installer.bat
rem          installer.bat "D:\SteamLibrary\steamapps\common\GarrysMod"
rem ------------------------------------------------------------

set "SRC=%~dp0"
if "%SRC:~-1%"=="\" set "SRC=%SRC:~0,-1%"

if not exist "%SRC%\addon.json" (
    echo [ERROR] addon.json not found in "%SRC%".
    echo Put installer.bat in the Hotloader folder and run it again.
    goto :fail
)

rem ---- Find Garry's Mod --------------------------------------
set "GMOD="

if not "%~1"=="" set "GMOD=%~1"

if not defined GMOD (
    for /f "tokens=2,*" %%A in ('reg query "HKCU\Software\Valve\Steam" /v SteamPath 2^>nul ^| find "SteamPath"') do (
        set "STEAM=%%B"
    )
    if defined STEAM (
        set "STEAM=!STEAM:/=\!"
        if exist "!STEAM!\steamapps\common\GarrysMod\garrysmod" set "GMOD=!STEAM!\steamapps\common\GarrysMod"
    )
)

if not defined GMOD if exist "%ProgramFiles(x86)%\Steam\steamapps\common\GarrysMod\garrysmod" set "GMOD=%ProgramFiles(x86)%\Steam\steamapps\common\GarrysMod"
if not defined GMOD if exist "%ProgramFiles%\Steam\steamapps\common\GarrysMod\garrysmod" set "GMOD=%ProgramFiles%\Steam\steamapps\common\GarrysMod"

if not defined GMOD (
    echo Could not find Garry's Mod automatically.
    set /p "GMOD=Enter the full path to your GarrysMod folder: "
)

set "GMOD=%GMOD:"=%"
if "%GMOD:~-1%"=="\" set "GMOD=%GMOD:~0,-1%"

if not exist "%GMOD%\garrysmod" (
    echo [ERROR] "%GMOD%\garrysmod" does not exist. Check the path.
    goto :fail
)

echo.
echo Source : %SRC%
echo Target : %GMOD%\garrysmod
echo.

rem ---- Install binary modules --------------------------------
set "BIN=%GMOD%\garrysmod\lua\bin"
if not exist "%BIN%" mkdir "%BIN%"

set /a COUNT=0
for %%F in ("%SRC%\gmcl_*_win64.dll" "%SRC%\gmsv_*_win64.dll" "%SRC%\gmcl_*_win32.dll" "%SRC%\gmsv_*_win32.dll") do (
    if exist "%%~F" (
        copy /Y "%%~F" "%BIN%\" >nul
        if errorlevel 1 (
            echo [ERROR] Failed to copy %%~nxF
            goto :fail
        )
        echo Installed module: %%~nxF
        set /a COUNT+=1
    )
)

if !COUNT! EQU 0 (
    echo [ERROR] No module DLLs found next to this script.
    goto :fail
)

rem ---- Install addon files (lua + addon.json) ----------------
set "ADDON=%GMOD%\garrysmod\addons\Hotloader"
if not exist "%ADDON%" mkdir "%ADDON%"

if exist "%SRC%\lua" (
    xcopy "%SRC%\lua" "%ADDON%\lua\" /E /I /Y /Q >nul
    if errorlevel 1 (
        echo [ERROR] Failed to copy the lua folder.
        goto :fail
    )
    echo Installed addon files: %ADDON%\lua
)
copy /Y "%SRC%\addon.json" "%ADDON%\" >nul
echo Installed addon.json

echo.
echo Done. Restart Garry's Mod (or your server) to load Hotloader.
echo Note: win64 modules only load on the x86-64 branch of Garry's Mod.
echo.
pause
exit /b 0

:fail
echo.
echo Installation did not finish.
pause
exit /b 1
