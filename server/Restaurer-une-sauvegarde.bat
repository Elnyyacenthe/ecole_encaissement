@echo off
rem Restaure une sauvegarde (remplace TOUTES les donnees actuelles). Fermez COSBIMP sur tous les PC avant.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Restaurer-Sauvegarde.ps1"
echo.
pause
