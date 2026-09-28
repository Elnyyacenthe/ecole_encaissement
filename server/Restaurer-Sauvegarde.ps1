# Restauration d'une sauvegarde COSBIMP (a lancer sur le PC serveur, COSBIMP ferme sur tous les PC).
# REMPLACE toutes les donnees actuelles par celles de la sauvegarde choisie.
# Avant de restaurer, une sauvegarde de securite de l'etat actuel est faite automatiquement.
# (Texte sans accents : PowerShell 5.1.)
param(
    [string]$File = '',
    [int]$Port = 3307,
    [string]$RootPassword = 'CosbimpRoot#2026',
    [string]$Database = 'cosbimp_scolarite',
    [string]$BackupDir = (Join-Path $env:ProgramData 'COSBIMP\backups'),
    [string]$MariaBin = (Join-Path $PSScriptRoot 'mariadb\bin'),
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$mysql = Join-Path $MariaBin 'mariadb.exe'
$common = @('-uroot', "-p$RootPassword", '-h127.0.0.1', "-P$Port")

if (-not $File) {
    $files = @(Get-ChildItem $BackupDir -Filter 'cosbimp_*.sql.gz' -File | Sort-Object LastWriteTime -Descending | Select-Object -First 15)
    if ($files.Count -eq 0) { Write-Output "Aucune sauvegarde trouvee dans $BackupDir"; exit 1 }
    Write-Output 'Sauvegardes disponibles (la plus recente en premier) :'
    for ($i = 0; $i -lt $files.Count; $i++) {
        Write-Output ("  [{0}] {1}   {2:dd/MM/yyyy HH:mm}   {3} Ko" -f ($i + 1), $files[$i].Name, $files[$i].LastWriteTime, [math]::Round($files[$i].Length / 1KB))
    }
    $choice = Read-Host 'Numero de la sauvegarde a restaurer'
    $n = 0
    if (-not [int]::TryParse($choice, [ref]$n) -or $n -lt 1 -or $n -gt $files.Count) { Write-Output 'Choix invalide.'; exit 1 }
    $File = $files[$n - 1].FullName
}
if (-not (Test-Path $File)) { Write-Output "Fichier introuvable : $File"; exit 1 }

if (-not $Force) {
    Write-Output ''
    Write-Output "ATTENTION : toutes les donnees actuelles vont etre REMPLACEES par : $File"
    $answer = Read-Host 'Tapez OUI (en majuscules) pour continuer'
    if ($answer -cne 'OUI') { Write-Output 'Annule.'; exit 1 }
}

# Sauvegarde de securite de l'etat actuel.
$safety = Join-Path $PSScriptRoot 'Sauvegarde.ps1'
if (Test-Path $safety) {
    & $safety -Source 'avant-restauration' -Port $Port -RootPassword $RootPassword -Database $Database -BackupDir $BackupDir -MariaBin $MariaBin | Out-Null
}

# Decompression dans un fichier temporaire.
$sql = Join-Path $BackupDir ('restauration_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.sql')
$in = [IO.File]::OpenRead($File)
$gz = New-Object IO.Compression.GZipStream($in, [IO.Compression.CompressionMode]::Decompress)
$out = [IO.File]::Create($sql)
try { $gz.CopyTo($out) } finally { $out.Dispose(); $gz.Dispose(); $in.Dispose() }

try {
    & $mysql @common -e "DROP DATABASE IF EXISTS ``$Database``; CREATE DATABASE ``$Database`` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    if ($LASTEXITCODE -ne 0) { throw 'Impossible de recreer la base.' }
    $sqlPath = $sql.Replace('\', '/')
    & $mysql @common --default-character-set=utf8mb4 $Database -e "SOURCE $sqlPath"
    if ($LASTEXITCODE -ne 0) { throw 'Import de la sauvegarde echoue.' }
    Write-Output ''
    Write-Output 'Restauration terminee. Relancez COSBIMP sur les PC.'
}
finally {
    Remove-Item $sql -Force -ErrorAction SilentlyContinue
}
