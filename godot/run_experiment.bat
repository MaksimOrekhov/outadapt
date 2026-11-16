@echo off
rem PRO-152: playtest of the adaptive swarm experiment (signature + counter-strain incubation).
rem New runs in this session use the experimental swarm model; loaded saves keep their own model.
rem Per-wave playtest logs: %APPDATA%\Godot\app_userdata\Outadapt\playtest\
cd /d "%~dp0"
start "" "D:\Godot\Godot_v4.7.2-stable_win64.exe" --path . -- --swarm=signature
