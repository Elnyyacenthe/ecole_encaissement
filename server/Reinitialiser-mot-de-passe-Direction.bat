@echo off
rem Secours : nouveau mot de passe provisoire pour le compte Direction.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Reinitialiser-Direction.ps1"
echo.
pause
