@echo off
rem PRO-141: two spatially separated portals, the second opens in the middle of the run. Dev only: never in normal runs.
rem   run_portal.bat                    - technical map portal_a, seed 1003; portal 2 opens at wave 18, warning from wave 15, 50% of enemies
rem   run_portal.bat b [seed]           - technical map portal_b
rem   run_portal.bat a 1003 control      - control on the same map: the second portal never opens (one active portal)
rem   run_portal.bat a 1003 early       - hypothesis variant: opens at wave 16, warning from wave 13
rem   run_portal.bat a 1003 late        - hypothesis variant: opens at wave 21, warning from wave 18
rem seed fixes the map, waves and genes for every new run in this session (same seed = same waves).
rem Enemies of waves before the opening wave all use portal 1 (as on one portal). Playtest protocol: docs\architecture\two-portal-experiment.md
rem Wave logs: %APPDATA%\Godot\app_userdata\Outadapt\playtest\
setlocal
cd /d "%~dp0"
set MAP=portal_a
if /i "%~1"=="b" set MAP=portal_b
set SEEDARG=--fixed-seed=1003
if not "%~2"=="" set SEEDARG=--fixed-seed=%~2
set PARG=
if /i "%~3"=="control" set PARG=--portal-open=999 --portal-announce=999
if /i "%~3"=="early" set PARG=--portal-open=16 --portal-announce=13
if /i "%~3"=="late" set PARG=--portal-open=21 --portal-announce=18
set TAG=%MAP%
if not "%PARG%"=="" set TAG=%MAP%-%~3
set REV=unknown
for /f %%i in ('git rev-parse --short HEAD 2^>nul') do set REV=%%i
start "" "D:\Godot\Godot_v4.7.2-stable_win64.exe" --path . -- --map=%MAP% --playtest %SEEDARG% %PARG% --build=%REV%-%TAG%
