@echo off
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -File "%~dp0Fix-OppoTun.ps1" -Action Fix
if errorlevel 1 pause
