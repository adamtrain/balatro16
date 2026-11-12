@echo off
rem Copies the mod into Balatro's Mods folder. Lovely must already be installed
rem (version.dll next to Balatro.exe).
setlocal
set "DEST=%APPDATA%\Balatro\Mods\BalatroMulti"
if not exist "%DEST%" mkdir "%DEST%"
copy /Y "%~dp0mod\BalatroMulti\lovely.toml" "%DEST%\" >nul
copy /Y "%~dp0mod\BalatroMulti\multi.lua" "%DEST%\" >nul
if errorlevel 1 (
    echo Install failed.
    exit /b 1
)
echo Installed to "%DEST%"
endlocal
