@echo off
rem PRO-115: live playtest launcher for the adaptive swarm experiment (PRO-152).
rem   run_playtest.bat on  [seed] [noworkshop]   - experimental swarm
rem   run_playtest.bat off [seed] [noworkshop]   - control run, same logging
rem seed fixes the map for every new run in this session (owner A/B on the same seed/family);
rem noworkshop disables Workshop bonuses. Difficulty is chosen in the menu.
rem Logs (one .jsonl per run): %APPDATA%\Godot\app_userdata\Outadapt\playtest\
rem Protocol: docs\balance\pro152-live-playtest.md
setlocal
cd /d "%~dp0"
set MODE=%~1
if "%MODE%"=="" set MODE=on
set SWARM=
if /i "%MODE%"=="on" set SWARM=--swarm=signature
set SEEDARG=
if not "%~2"=="" set SEEDARG=--fixed-seed=%~2
set WS=
if /i "%~3"=="noworkshop" set WS=--no-workshop
set REV=unknown
for /f %%i in ('git rev-parse --short HEAD 2^>nul') do set REV=%%i
start "" "D:\Godot\Godot_v4.7.2-stable_win64.exe" --path . -- --playtest %SWARM% %SEEDARG% %WS% --build=%REV%-%MODE%
