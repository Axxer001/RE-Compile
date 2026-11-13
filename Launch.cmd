@echo off
rem RE:Compile launcher. Prefers the encrypted Windows build; falls back to
rem running the project with the installed Godot 4.7.2 (godot or godot_console on PATH).
setlocal
set "HERE=%~dp0"
set "BUILD=%HERE%..\RECompile-FPS-build\RECompile.exe"
if exist "%BUILD%" (
  start "" "%BUILD%"
  exit /b 0
)
where godot >nul 2>nul && (
  start "" godot --path "%HERE%."
  exit /b 0
)
where godot_console >nul 2>nul && (
  start "" godot_console --path "%HERE%."
  exit /b 0
)
echo RE:Compile: no build found at "%BUILD%" and no Godot on PATH.
echo Build it with the "Windows Desktop (encrypted)" export preset, or install Godot 4.7.2.
pause
exit /b 1
