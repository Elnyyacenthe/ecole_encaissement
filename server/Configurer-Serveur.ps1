# Prepare le serveur COSBIMP : base de donnees, pare-feu, service Windows,
# sauvegardes automatiques. Lance UNE SEULE FOIS par Installer.bat (en tant
# qu'administrateur), pour que l'application elle-meme n'ait plus jamais
# besoin de demander d'autorisation, y compris au tout premier lancement.
# Sans danger a relancer : tout est idempotent.
# (Texte sans accents : PowerShell 5.1.)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$bin = Join-Path $root 'mariadb\bin'
$port = 3307
$rootPassword = 'CosbimpRoot#2026'
$serviceName = 'COSBIMPDB'
$firewallRule = 'COSBIMP Base de donnees'
$backupTaskName = 'COSBIMP Sauvegarde'
$appUser = 'cosbimp'
$appPassword = 'Cosbimp@2026'
$appDb = 'cosbimp_scolarite'

if (-not (Test-Path (Join-Path $bin 'mariadbd.exe'))) {
    Write-Output 'Ce dossier ne contient pas la base embarquee (poste client) : rien a faire.'
    exit 0
}

$programData = Join-Path $env:ProgramData 'COSBIMP'
$dataDir = Join-Path $programData 'data'
$ini = Join-Path $programData 'my.ini'
New-Item -ItemType Directory -Force $programData | Out-Null

if (-not (Test-Path (Join-Path $dataDir 'mysql'))) {
    Write-Output 'Installation de la base de donnees (premiere utilisation)...'
    & (Join-Path $bin 'mariadb-install-db.exe') "--datadir=$dataDir" "--port=$port" "--password=$rootPassword"
    if ($LASTEXITCODE -ne 0) { throw 'mariadb-install-db a echoue.' }
}

function Fwd([string]$p) { $p.Replace('\', '/') }
@"
[mysqld]
basedir=$(Fwd $root)/mariadb
datadir=$(Fwd $dataDir)
port=$port
bind-address=0.0.0.0
character-set-server=utf8mb4
collation-server=utf8mb4_unicode_ci
max_connections=100
innodb_buffer_pool_size=128M
log-error=$(Fwd $programData)/error.log
"@ | Set-Content -Encoding ascii $ini

Write-Output 'Ouverture du pare-feu pour le reseau local...'
netsh advfirewall firewall show rule name="$firewallRule" | Out-Null
if ($LASTEXITCODE -ne 0) {
    netsh advfirewall firewall add rule name="$firewallRule" dir=in action=allow protocol=TCP localport=$port profile=any | Out-Null
}

Write-Output 'Installation du service (demarrage automatique avec Windows)...'
if (-not (Get-Service -Name $serviceName -ErrorAction SilentlyContinue)) {
    & (Join-Path $bin 'mariadbd.exe') --install $serviceName "--defaults-file=$ini" | Out-Null
}
Set-Service -Name $serviceName -StartupType Automatic
if ((Get-Service -Name $serviceName).Status -ne 'Running') { Start-Service -Name $serviceName }

Write-Output 'Attente du demarrage de la base de donnees...'
$ok = $false
for ($i = 0; $i -lt 60; $i++) {
    try {
        $client = New-Object Net.Sockets.TcpClient('127.0.0.1', $port)
        $client.Close()
        $ok = $true
        break
    } catch { Start-Sleep -Milliseconds 500 }
}
if (-not $ok) { throw "La base de donnees ne repond pas sur le port $port (voir $programData\error.log)." }

Write-Output "Preparation du compte de l'application..."
$mysql = Join-Path $bin 'mariadb.exe'
$common = @('-uroot', "-p$rootPassword", '-h127.0.0.1', "-P$port")
& $mysql @common -e "CREATE DATABASE IF NOT EXISTS $appDb CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
if ($LASTEXITCODE -ne 0) { throw "Impossible de creer la base $appDb." }
foreach ($h in @('%', 'localhost')) {
    & $mysql @common -e "CREATE USER IF NOT EXISTS '$appUser'@'$h' IDENTIFIED BY '$appPassword'; GRANT ALL PRIVILEGES ON $appDb.* TO '$appUser'@'$h';"
}
& $mysql @common -e 'FLUSH PRIVILEGES;'

$backupScript = Join-Path $root 'Sauvegarde.ps1'
if (Test-Path $backupScript) {
    Write-Output 'Sauvegardes automatiques (12h30 et 19h00)...'
    $arg = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$backupScript`" -Source planifiee"
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg
    $triggers = @((New-ScheduledTaskTrigger -Daily -At '12:30'), (New-ScheduledTaskTrigger -Daily -At '19:00'))
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 30)
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName $backupTaskName -Action $action -Trigger $triggers -Settings $settings -Principal $principal -Force | Out-Null
}

Write-Output ''
Write-Output 'Serveur pret. Vous pouvez fermer cette fenetre et ouvrir COSBIMP.'
