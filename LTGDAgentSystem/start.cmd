@echo off
set "TSX_TSCONFIG_PATH=%~dp0..\PiAgent\tsconfig.json"
cd /d "%~dp0..\games\system"
powershell.exe -NoProfile -NoExit -ExecutionPolicy Bypass -File "%~dp0..\PiAgent\pi-test.ps1" --extension "%~dp0godot-pat\index.ts" %*
