@echo off
rem PRO-139: isolated fork prototype (one portal, two branches, merge before the castle).
rem   run_fork.bat           - equal branches (map "fork")
rem   run_fork.bat uneven    - short north / long south branch (map "fork_uneven")
rem Enemies alternate between branches (0, 1, 0, 1, ...). Technical maps only: never used in normal runs.
setlocal
cd /d "%~dp0"
set MAP=fork
if /i "%~1"=="uneven" set MAP=fork_uneven
start "" "D:\Godot\Godot_v4.7.2-stable_win64.exe" --path . -- --map=%MAP%
