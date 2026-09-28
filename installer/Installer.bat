@echo off
rem Installe COSBIMP dans C:\COSBIMP et cree un raccourci sur le Bureau.
rem Sur le PC serveur, prepare aussi le reseau, le service et les sauvegardes
rem automatiques en une seule fois, pour que COSBIMP ne redemande plus jamais
rem d'autorisation ensuite.
setlocal
set "SRC=%~dp0"
set "DEST=C:\COSBIMP"

if /I "%~1"=="ELEVATED" goto :install
if not exist "%SRC%mariadb\bin\mariadbd.exe" goto :install

net session >nul 2>&1
if "%errorlevel%"=="0" goto :install

echo.
echo  Ce PC va devenir le SERVEUR. Une autorisation Windows va s'afficher :
echo  necessaire UNE SEULE FOIS pour preparer le reseau, le service et les
echo  sauvegardes automatiques. Cliquez sur Oui.
echo.
powershell -NoProfile -Command "try { Start-Process -FilePath '%~f0' -ArgumentList 'ELEVATED' -Verb RunAs -ErrorAction Stop } catch { exit 1 }"
if errorlevel 1 (
  echo  Autorisation refusee : installation en mode limite.
  echo  Windows la redemandera au premier lancement de COSBIMP.
  echo.
  goto :install
)
exit /b

:install
echo.
echo  Installation de COSBIMP dans %DEST% ...
if not exist "%DEST%" mkdir "%DEST%"
xcopy "%SRC%*" "%DEST%\" /E /I /Y /Q >nul
if errorlevel 1 (
  echo  ERREUR : la copie a echoue.
  pause
  exit /b 1
)

powershell -NoProfile -Command "$s=(New-Object -ComObject WScript.Shell).CreateShortcut([Environment]::GetFolderPath('Desktop')+'\COSBIMP.lnk'); $s.TargetPath='%DEST%\cosbimp_scolarite.exe'; $s.WorkingDirectory='%DEST%'; $s.IconLocation='%DEST%\cosbimp_scolarite.exe'; $s.Save()"

if not exist "%DEST%\mariadb\bin\mariadbd.exe" goto :done

net session >nul 2>&1
if not "%errorlevel%"=="0" (
  echo.
  echo  Ce PC est le SERVEUR mais l'autorisation Windows a ete refusee :
  echo  au premier lancement de COSBIMP, Windows la redemandera. Cliquez sur
  echo  Oui pour terminer la configuration.
  goto :done
)

echo.
echo  Configuration du serveur ^(reseau, service, sauvegardes^) ...
powershell -NoProfile -ExecutionPolicy Bypass -File "%DEST%\Configurer-Serveur.ps1"
if errorlevel 1 (
  echo.
  echo  ATTENTION : la configuration automatique a rencontre un probleme.
  echo  Relancez Installer.bat, ou COSBIMP terminera seul a l'ouverture.
) else (
  echo  Serveur configure : demarrage automatique avec Windows, sauvegardes activees.
  echo  Le lancement de COSBIMP ne demandera plus aucune autorisation.
)

:done
echo.
echo  Installation terminee.
echo  Ouvrez COSBIMP avec le raccourci du Bureau.
echo.
pause
