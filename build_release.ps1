# Construit les deux versions installables de l'application dans dist\ :
#   COSBIMP-Serveur : application + base de données embarquée (1 seul PC : celui qui héberge les données)
#   COSBIMP-Poste   : application seule (tous les autres PC ; ils trouvent le serveur automatiquement)
# Chaque dossier contient Installer.bat (installation en un double-clic).
#
# Usage : powershell -ExecutionPolicy Bypass -File build_release.ps1

param([string]$Dist = 'dist')   # dossier de sortie (par defaut : dist)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$running = Get-Process cosbimp_scolarite -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -like "$PSScriptRoot\$Dist\*" }
if ($running) { throw "COSBIMP est ouvert depuis le dossier $Dist : fermez-le puis relancez ce script." }

if (-not (Test-Path 'server\mariadb\bin\mariadbd.exe')) {
    throw "Dossier server\mariadb introuvable : la base embarquée est nécessaire pour la version Serveur."
}

flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw 'Échec de flutter build windows' }

$release = 'build\windows\x64\runner\Release'
$dist = $Dist
if (Test-Path $dist) { Remove-Item $dist -Recurse -Force }

$poste = "$dist\COSBIMP-Poste"
$serveur = "$dist\COSBIMP-Serveur"
New-Item -ItemType Directory -Force $poste, $serveur | Out-Null

foreach ($target in @($poste, $serveur)) {
    Copy-Item "$release\*" $target -Recurse
    Copy-Item 'installer\Installer.bat' $target

    # Runtime Visual C++ : évite d'exiger une installation préalable sur les autres PC.
    foreach ($dll in 'vcruntime140.dll', 'vcruntime140_1.dll', 'msvcp140.dll') {
        $src = Join-Path $env:SystemRoot "System32\$dll"
        if ((Test-Path $src) -and -not (Test-Path (Join-Path $target $dll))) {
            Copy-Item $src $target
        }
    }
}
Copy-Item 'server\mariadb' "$serveur\mariadb" -Recurse
# Scripts de sauvegarde / restauration / secours (uniquement sur le PC serveur).
Copy-Item 'server\*.ps1' $serveur
Copy-Item 'server\*.bat' $serveur

Write-Host "OK : $poste et $serveur"
