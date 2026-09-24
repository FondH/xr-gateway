@echo off
setlocal
pwsh.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0sub2api-gui.ps1"
if errorlevel 1 pause
