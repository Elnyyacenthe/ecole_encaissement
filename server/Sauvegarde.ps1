# Sauvegarde de la base COSBIMP (a lancer sur le PC serveur).
#  - fichier compresse : <BackupDir>\cosbimp_AAAA-MM-JJ_HHMMSS.sql.gz
#  - copie optionnelle vers un autre dossier / disque (reglage "backup_copy_dir" de l'application)
#  - resultat inscrit dans la table backup_log (affiche dans Parametres > Sauvegardes)
# Lance automatiquement par la tache planifiee "COSBIMP Sauvegarde". (Texte sans accents : PowerShell 5.1.)
param(
    [string]$Source = 'manuelle',
    [int]$Port = 3307,
    [string]$RootPassword = 'CosbimpRoot#2026',
    [string]$Database = 'cosbimp_scolarite',
    [string]$BackupDir = (Join-Path $env:ProgramData 'COSBIMP\backups'),
    [string]$MariaBin = (Join-Path $PSScriptRoot 'mariadb\bin')
)

$ErrorActionPreference = 'Stop'
$KeepRecent = 10   # on garde toujours les 10 plus recentes
$KeepDays = 60     # les autres sont supprimees au-dela de 60 jours

$mysql = Join-Path $MariaBin 'mariadb.exe'
$dump = Join-Path $MariaBin 'mariadb-dump.exe'
$common = @('-uroot', "-p$RootPassword", '-h127.0.0.1', "-P$Port")

function Invoke-Sql([string]$Sql) { & $mysql @common $Database -N -B -r -e $Sql }
function Esc([string]$s) { return $s.Replace('\', '\\').Replace("'", "''") }

function Write-Log([string]$Status, [string]$File, [long]$Size, [string]$Message, [string]$Copied) {
    try {
        $copiedSql = if ($Copied) { "'" + (Esc $Copied) + "'" } else { 'NULL' }
        Invoke-Sql ("INSERT INTO backup_log (file_name, size_bytes, status, message, copied_to, source) VALUES ('" +
            (Esc $File) + "', $Size, '$Status', '" + (Esc $Message) + "', $copiedSql, '" + (Esc $Source) + "')") | Out-Null
        Invoke-Sql 'DELETE FROM backup_log WHERE id <= (SELECT m FROM (SELECT MAX(id) - 200 AS m FROM backup_log) t)' | Out-Null
    } catch { }
}

function Remove-OldBackups([string]$Dir) {
    $files = Get-ChildItem $Dir -Filter 'cosbimp_*.sql.gz' -File | Sort-Object LastWriteTime -Descending
    $files | Select-Object -Skip $KeepRecent |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$KeepDays) } |
        Remove-Item -Force
}

$stamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$name = "cosbimp_$stamp.sql.gz"
$tmp = Join-Path $BackupDir "cosbimp_$stamp.sql.tmp"
$target = Join-Path $BackupDir $name

try {
    New-Item -ItemType Directory -Force $BackupDir | Out-Null

    & $dump @common --single-transaction --routines --triggers --events --default-character-set=utf8mb4 "--result-file=$tmp" $Database
    if ($LASTEXITCODE -ne 0) { throw "mariadb-dump a echoue (code $LASTEXITCODE)" }
    if (-not (Test-Path $tmp) -or (Get-Item $tmp).Length -lt 2000) { throw 'Sauvegarde vide' }
    if (-not ((Get-Content $tmp -Tail 3) -match 'Dump completed')) { throw 'Sauvegarde incomplete (fin du fichier absente)' }

    $in = [IO.File]::OpenRead($tmp)
    $out = [IO.File]::Create($target)
    $gz = New-Object IO.Compression.GZipStream($out, [IO.Compression.CompressionMode]::Compress)
    try { $in.CopyTo($gz) } finally { $gz.Dispose(); $out.Dispose(); $in.Dispose() }
    Remove-Item $tmp -Force
    $size = (Get-Item $target).Length

    $message = 'Sauvegarde reussie'
    $copied = ''
    $extra = ("" + (Invoke-Sql "SELECT CONVERT(COALESCE(setting_value, '') USING utf8mb4) FROM app_settings WHERE setting_key = 'backup_copy_dir'")).Trim()
    if ($extra -and $extra -notmatch '^([A-Za-z]:\\|\\\\)') {
        # Un chemin relatif creerait un dossier n'importe ou : on refuse.
        $message = "Sauvegarde reussie, mais copie externe ignoree : chemin invalide ($extra). Choisissez un dossier complet (ex. E:\Sauvegardes)."
    }
    elseif ($extra) {
        try {
            New-Item -ItemType Directory -Force $extra | Out-Null
            Copy-Item $target $extra -Force
            Remove-OldBackups $extra
            $copied = $extra
        } catch {
            $message = "Sauvegarde reussie, mais copie externe impossible ($extra) : " + $_.Exception.Message
        }
    }
    Remove-OldBackups $BackupDir
    Write-Log 'OK' $name $size $message $copied
    Write-Output "OK $name ($([math]::Round($size / 1KB)) Ko)"
    exit 0
}
catch {
    if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
    Write-Log 'ERREUR' $name 0 $_.Exception.Message ''
    Write-Output ("ERREUR : " + $_.Exception.Message)
    exit 1
}
