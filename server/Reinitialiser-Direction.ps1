# Secours : redonne un mot de passe provisoire au compte Direction si son mot de passe est perdu.
# A lancer sur le PC serveur. La Direction devra choisir un nouveau mot de passe a sa prochaine connexion.
# (Texte sans accents : PowerShell 5.1.)
param(
    [string]$NewPassword = '',
    [int]$Port = 3307,
    [string]$RootPassword = 'CosbimpRoot#2026',
    [string]$Database = 'cosbimp_scolarite',
    [string]$MariaBin = (Join-Path $PSScriptRoot 'mariadb\bin')
)

$ErrorActionPreference = 'Stop'
$mysql = Join-Path $MariaBin 'mariadb.exe'
$common = @('-uroot', "-p$RootPassword", '-h127.0.0.1', "-P$Port")

if (-not $NewPassword) { $NewPassword = Read-Host 'Nouveau mot de passe provisoire (6 caracteres minimum)' }
if ($NewPassword.Length -lt 6) { Write-Output 'Mot de passe trop court (6 caracteres minimum).'; exit 1 }

# Meme algorithme que l'application : PBKDF2-HMAC-SHA256, 20000 iterations, sel aleatoire de 16 octets.
$saltBytes = New-Object byte[] 16
[Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($saltBytes)
$iterations = 20000
$kdf = New-Object Security.Cryptography.Rfc2898DeriveBytes($NewPassword, $saltBytes, $iterations, [Security.Cryptography.HashAlgorithmName]::SHA256)
$hash = ($kdf.GetBytes(32) | ForEach-Object { $_.ToString('x2') }) -join ''
$salt = ($saltBytes | ForEach-Object { $_.ToString('x2') }) -join ''

$sql = "UPDATE users SET password_hash = '$hash', salt = '$salt', iterations = $iterations, must_change_password = 1, is_active = 1 WHERE role = 'SUPER_ADMIN' ORDER BY id LIMIT 1; SELECT ROW_COUNT();"
$result = (& $mysql @common $Database -N -B -e $sql) | Select-Object -Last 1
if ($LASTEXITCODE -ne 0 -or "$result".Trim() -ne '1') { Write-Output 'Aucun compte Direction trouve.'; exit 1 }

$login = (& $mysql @common $Database -N -B -e "SELECT username FROM users WHERE role = 'SUPER_ADMIN' ORDER BY id LIMIT 1").Trim()
Write-Output "Mot de passe provisoire enregistre pour le compte Direction (identifiant : $login)."
Write-Output 'La personne devra choisir son propre mot de passe a la prochaine connexion.'
