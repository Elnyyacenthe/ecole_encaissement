@echo off
rem Lance une sauvegarde immediate de la base COSBIMP.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Sauvegarde.ps1" -Source manuelle
echo.
pause
