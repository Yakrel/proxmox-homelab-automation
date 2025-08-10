param(
  [Parameter(Mandatory=$true)][string]$Stack,
  [Parameter(Mandatory=$true)][string]$Passphrase
)

$root = Split-Path -Parent $PSScriptRoot
$envPath = Join-Path $root "docker/$Stack/.env"
$outPath = Join-Path $root "docker/$Stack/.env.enc"

if (!(Test-Path $envPath)) {
  Write-Error ".env not found: $envPath"
  exit 1
}

# Try Windows OpenSSL if installed via Chocolatey/WinGet, otherwise use .NET AES
function Encrypt-OpenSsl {
  param([string]$InFile, [string]$OutFile, [string]$Pw)
  $openssl = (Get-Command openssl -ErrorAction SilentlyContinue)
  if ($openssl) {
    & $openssl.Path enc -aes-256-cbc -salt -pbkdf2 -pass pass:$Pw -in $InFile -out $OutFile
    return $LASTEXITCODE
  } else {
    return -1
  }
}

$rc = Encrypt-OpenSsl -InFile $envPath -OutFile $outPath -Pw $Passphrase
if ($rc -eq 0) {
  Write-Host "Encrypted with OpenSSL to $outPath"
  exit 0
}

# Fallback: .NET AES (AES-256-CBC with PBKDF2) to be compatible with openssl -pbkdf2
Add-Type -AssemblyName System.Security
Add-Type -AssemblyName System.Security.Cryptography

function Get-Bytes($s){ [Text.Encoding]::UTF8.GetBytes($s) }

$salt = New-Object byte[] 16
[Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($salt)
$iterations = 10000
$kdf = New-Object System.Security.Cryptography.Rfc2898DeriveBytes (Get-Bytes $Passphrase), $salt, $iterations, [System.Security.Cryptography.HashAlgorithmName]::SHA256
$key = $kdf.GetBytes(32)
$iv  = $kdf.GetBytes(16)

$aes = [System.Security.Cryptography.Aes]::Create()
$aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
$aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
$aes.Key = $key
$aes.IV  = $iv

$encryptor = $aes.CreateEncryptor()
$inBytes = [IO.File]::ReadAllBytes($envPath)
$outStream = New-Object IO.MemoryStream
$cryptoStream = New-Object Security.Cryptography.CryptoStream($outStream, $encryptor, [IO.CryptoStreamMode]::Write)
$cryptoStream.Write($inBytes, 0, $inBytes.Length)
$cryptoStream.FlushFinalBlock()
$cipher = $outStream.ToArray()
$cryptoStream.Dispose(); $outStream.Dispose(); $encryptor.Dispose(); $aes.Dispose()

# Write an OpenSSL-compatible header? Simpler approach: our deploy decrypt uses openssl -d; to remain compatible, prefer using OpenSSL above.
# Here we write a simple container: ["Salted__"][salt 16b][cipher]
$prefix = [Text.Encoding]::ASCII.GetBytes("Salted__")
$final = New-Object byte[] ($prefix.Length + $salt.Length + $cipher.Length)
[Array]::Copy($prefix, 0, $final, 0, $prefix.Length)
[Array]::Copy($salt, 0, $final, $prefix.Length, $salt.Length)
[Array]::Copy($cipher, 0, $final, $prefix.Length + $salt.Length, $cipher.Length)
[IO.File]::WriteAllBytes($outPath, $final)
Write-Host "Encrypted with .NET fallback to $outPath"
