@echo off
rem Starts N copies of Balatro that all receive the same input.
rem
rem   launch.bat [count] [path\to\Balatro.exe]
rem
rem count is 2, 4, 8 or 16 (default 4). If Balatro is not in the default Steam
rem folder, pass the path to Balatro.exe or set BALATRO_EXE.
setlocal

set "N=%~1"
if "%N%"=="" set "N=4"
if "%N%"=="1" goto count_ok
if "%N%"=="2" goto count_ok
if "%N%"=="4" goto count_ok
if "%N%"=="8" goto count_ok
if "%N%"=="16" goto count_ok
echo Instance count must be 2, 4, 8 or 16.
exit /b 1
:count_ok

set "GAME=%~2"
if "%GAME%"=="" set "GAME=%BALATRO_EXE%"
if "%GAME%"=="" set "GAME=%ProgramFiles(x86)%\Steam\steamapps\common\Balatro\Balatro.exe"
if exist "%GAME%" goto game_ok
echo Could not find Balatro.exe at:
echo   "%GAME%"
echo Pass its path as the second argument, e.g.
echo   launch.bat 4 "D:\SteamLibrary\steamapps\common\Balatro\Balatro.exe"
exit /b 1
:game_ok
for %%F in ("%GAME%") do set "GAMEDIR=%%~dpF"

rem Tells the mod how many instances there are.
set "BALATRO_MULTI_N=%N%"

rem Optional settings (uncomment to change):
rem set "BALATRO_MULTI_DISPLAY=2"   which monitor to use
rem set "BALATRO_MULTI_FPS=60"      frame cap per instance
rem set "BALATRO_MULTI_STEAM=0"     no Steam integration in any instance
rem set "BALATRO_MULTI_LABEL=0"     hide the instance number in the corner
rem set "BALATRO_MULTI_PORT=47816"  local port the instances talk over

rem Lets instance 1 reach Steam when started outside the Steam client.
set "SteamAppId=2379780"
set "SteamGameId=2379780"

rem A click on a window that is not focused still counts as a click.
set "SDL_MOUSE_FOCUS_CLICKTHROUGH=1"
rem Every instance reads a connected controller, focused or not.
set "SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS=1"

for /L %%i in (1,1,%N%) do (
    set "BALATRO_MULTI_ID=%%i"
    start "" /D "%GAMEDIR%" "%GAME%"
)
endlocal
