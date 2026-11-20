@echo off
rem PRO-139 / PRO-213: fork maps (one portal, two roads, merge before the castle). Dev only: never in normal runs.
rem   run_fork.bat                 - generated fork, variant chosen by seed (new seed every run)
rem   run_fork.bat even [seed]     - generated fork with roads of almost equal length
rem   run_fork.bat skew [seed]     - generated fork with a long and a short road
rem   run_fork.bat proto           - PRO-139 technical map "fork" (equal branches)
rem   run_fork.bat uneven          - PRO-139 technical map "fork_uneven"
rem   run_fork.bat even 1003 ramp  - PRO-214: the second road is phased in (waves 1-2: 100/0, 3-4: 80/20, 5-6: 65/35, 7+: 50/50),
rem                                 the shorter road goes first; 'ramp-long' - the longer road goes first (skew: test both)
rem seed fixes the map for every new run in this session (same seed = same map, waves and genes).
rem Enemies alternate between roads (0, 1, 0, 1, ...). Playtest protocol: docs\architecture\static-forks.md
rem Wave logs (one .jsonl per run): %APPDATA%\Godot\app_userdata\Outadapt\playtest\
setlocal
cd /d "%~dp0"
set MAP=forks
if /i "%~1"=="even" set MAP=fork_even
if /i "%~1"=="skew" set MAP=fork_skew
if /i "%~1"=="proto" set MAP=fork
if /i "%~1"=="uneven" set MAP=fork_uneven
set SEEDARG=
if not "%~2"=="" set SEEDARG=--fixed-seed=%~2
set RAMPARG=
if /i "%~3"=="ramp" set RAMPARG=--route-ramp=pilot --route-lead=short
if /i "%~3"=="ramp-long" set RAMPARG=--route-ramp=pilot --route-lead=long
set TAG=%MAP%
if not "%RAMPARG%"=="" set TAG=%MAP%-%~3
set REV=unknown
for /f %%i in ('git rev-parse --short HEAD 2^>nul') do set REV=%%i
start "" "D:\Godot\Godot_v4.7.2-stable_win64.exe" --path . -- --map=%MAP% --playtest %SEEDARG% %RAMPARG% --build=%REV%-%TAG%
