param(
  [string]$Stack,
  [string]$Passphrase,
  [string]$OpenSslPath,
  [switch]$Decrypt,
  [string]$OutputDir
)

function RevealPlain($sec) {
  $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
  try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

$root = Split-Path -Parent $PSScriptRoot
$dockerDir = Join-Path $root 'docker'

if (!(Test-Path $dockerDir)) {
  Write-Error "docker directory not found at $dockerDir"
  exit 1
}

function Resolve-OpenSSL {
  param([string]$Override)
  if ($Override -and (Test-Path $Override)) { return (Resolve-Path $Override).Path }

  $cmd = Get-Command openssl -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($cmd -and $cmd.Path) { return $cmd.Path }

  $common = @(
    'C:\Program Files\OpenSSL-Win64\bin\openssl.exe',
    'C:\Program Files\Git\usr\bin\openssl.exe',
    'C:\Program Files\Git\mingw64\bin\openssl.exe'
  )
  foreach ($p in $common) { if (Test-Path $p) { return $p } }

  return $null
}

$opensslExe = Resolve-OpenSSL -Override $OpenSslPath
if (-not $opensslExe) {
  Write-Error @"
OpenSSL not found.
Install it (e.g., winget install -e ShiningLight.OpenSSL.Light), or point -OpenSslPath to openssl.exe.
If already installed but not on PATH, try (current session only):
  $env:Path += ';C:\Program Files\OpenSSL-Win64\bin'
Alternatively, Git for Windows often provides it at:
  C:\Program Files\Git\usr\bin\openssl.exe
"@
  exit 1
}
Write-Host "Using OpenSSL: $opensslExe" -ForegroundColor DarkGray

# Interactive operation menu (shown when -Decrypt not explicitly provided)
$Mode = $null
if ($PSBoundParameters.ContainsKey('Decrypt')) { if ($Decrypt) { $Mode = 'decrypt' } else { $Mode = 'encrypt' } }
if (-not $Mode) {
  Write-Host "Select operation:" -ForegroundColor Cyan
  Write-Host "  [1] Encrypt .env -> .env.enc"
  Write-Host "  [2] Decrypt .env.enc -> .env.dec"
  Write-Host "  [Q] Quit"
  $op = Read-Host "Choice"
  if ($op -match '^[Qq]$') { Write-Host "Exit."; exit 0 }
  if ($op -eq '2') { $Mode = 'decrypt' } else { $Mode = 'encrypt' }
  if ($Mode -eq 'decrypt' -and -not $PSBoundParameters.ContainsKey('OutputDir')) {
    $outPrompt = Read-Host "Optional output directory for decrypted files (Enter to use .env.dec next to stacks)"
    if ($outPrompt) { $OutputDir = $outPrompt }
  }
}

function Get-Candidates {
  param([string]$Mode)
  if ($Mode -eq 'decrypt') {
    return Get-ChildItem -Path $dockerDir -Directory | Where-Object { Test-Path (Join-Path $_.FullName '.env.enc') }
  } else {
    return Get-ChildItem -Path $dockerDir -Directory | Where-Object { Test-Path (Join-Path $_.FullName '.env') }
  }
}

# Discover stacks based on mode; offer auto-switch if none found
$candidates = Get-Candidates -Mode:$Mode
if (-not $candidates -or $candidates.Count -eq 0) {
  if ($Mode -eq 'decrypt') {
    $alt = Get-Candidates -Mode:'encrypt'
    if ($alt -and $alt.Count -gt 0) {
      Write-Host "No .env.enc files found, but plaintext .env files exist." -ForegroundColor Yellow
      $sw = Read-Host "Switch to Encrypt mode? (Y/n)"
      if ($sw -eq '' -or $sw -match '^[Yy]$') { $Mode = 'encrypt'; $candidates = $alt }
    }
  } elseif ($Mode -eq 'encrypt') {
    $alt = Get-Candidates -Mode:'decrypt'
    if ($alt -and $alt.Count -gt 0) {
      Write-Host "No plaintext .env files found, but .env.enc files exist." -ForegroundColor Yellow
      $sw = Read-Host "Switch to Decrypt mode? (Y/n)"
      if ($sw -eq '' -or $sw -match '^[Yy]$') {
        $Mode = 'decrypt'; $candidates = $alt
        if (-not $PSBoundParameters.ContainsKey('OutputDir')) {
          $outPrompt = Read-Host "Optional output directory for decrypted files (Enter to use .env.dec next to stacks)"
          if ($outPrompt) { $OutputDir = $outPrompt }
        }
      }
    }
  }
  if (-not $candidates -or $candidates.Count -eq 0) {
    if ($Mode -eq 'decrypt') { Write-Error "No encrypted files found under $dockerDir/*/.env.enc" }
    elseif ($Mode -eq 'encrypt') { Write-Error "No plaintext .env files found under $dockerDir/*/.env" }
    exit 1
  }
}

# Choose stacks
$stacks = @()
if ($Stack) {
  if ($Mode -eq 'decrypt') {
    if (-not (Test-Path (Join-Path $dockerDir "$Stack/.env.enc"))) {
      Write-Error ".env.enc not found for stack '$Stack' at docker/$Stack/.env.enc"; exit 1 }
  } elseif ($Mode -eq 'encrypt') {
    if (-not (Test-Path (Join-Path $dockerDir "$Stack/.env"))) {
      Write-Error ".env not found for stack '$Stack' at docker/$Stack/.env"; exit 1 }
  }
  $stacks = @($Stack)
} else {
  $label = '.env'
  if ($Mode -eq 'decrypt') { $label = '.env.enc' }
  Write-Host ("Found the following stacks with {0}:" -f $label) -ForegroundColor Cyan
  for ($i=0; $i -lt $candidates.Count; $i++) {
    $name = $candidates[$i].Name
    Write-Host ("  [{0}] {1}" -f ($i+1), $name)
  }
  Write-Host "  [A] All"
  if ($Mode -eq 'decrypt') {
    $choice = Read-Host "Select stacks to decrypt (e.g., 1,3 or A)"
  } else {
    $choice = Read-Host "Select stacks to encrypt (e.g., 1,3 or A)"
  }
  if ($choice -match '^[Aa]$') {
    $stacks = $candidates | ForEach-Object { $_.Name }
  } else {
    $indexes = $choice -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ }
    foreach ($idx in $indexes) {
      if ($idx -ge 1 -and $idx -le $candidates.Count) { $stacks += $candidates[$idx-1].Name }
    }
    if ($stacks.Count -eq 0) { Write-Error "No valid selection."; exit 1 }
  }
}

# Ask passphrase if not supplied (confirm on encrypt, single prompt on decrypt)
if (-not $Passphrase) {
  if ($Mode -eq 'decrypt') {
    $p = Read-Host "Enter decryption passphrase" -AsSecureString
    $Passphrase = RevealPlain $p
  } else {
    while ($true) {
      $p1 = Read-Host "Enter encryption passphrase" -AsSecureString
      $p2 = Read-Host "Confirm passphrase" -AsSecureString
      $s1 = RevealPlain $p1
      $s2 = RevealPlain $p2
      if ([string]::IsNullOrWhiteSpace($s1)) { Write-Host "Passphrase cannot be empty." -ForegroundColor Yellow; continue }
      if ($s1 -ne $s2) { Write-Host "Passphrases do not match. Try again." -ForegroundColor Yellow; continue }
      $Passphrase = $s1
      break
    }
  }
}

# Overwrite behavior
$overwriteAll = $false
$deletePlain = $false
if ($Mode -eq 'decrypt') {
  $ans = Read-Host "Overwrite existing output file if present? (Y/n)"
  if ($ans -eq '' -or $ans -match '^[Yy]$') { $overwriteAll = $true }
} else {
  $ans = Read-Host "Overwrite existing .env.enc if present? (Y/n)"
  if ($ans -eq '' -or $ans -match '^[Yy]$') { $overwriteAll = $true }
  $ans2 = Read-Host "Delete plaintext .env after successful encryption? (y/N)"
  if ($ans2 -match '^[Yy]$') { $deletePlain = $true }
}

foreach ($s in $stacks) {
  if ($Mode -eq 'decrypt') {
    $inPath = Join-Path $dockerDir "$s/.env.enc"
    $outPath = if ($OutputDir) { if (!(Test-Path $OutputDir)) { New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null }; Join-Path $OutputDir "$s.env" } else { Join-Path $dockerDir "$s/.env.dec" }
    if (-not (Test-Path $inPath)) { Write-Host "Skipping $s (no .env.enc)." -ForegroundColor Yellow; continue }
    if ((Test-Path $outPath) -and -not $overwriteAll) { Write-Host "Skipping $s (output exists)." -ForegroundColor Yellow; continue }
    Write-Host "Decrypting $s -> $outPath" -ForegroundColor Green
    & "$opensslExe" enc -d -aes-256-cbc -pbkdf2 -pass "pass:$Passphrase" -in $inPath -out $outPath
    if ($LASTEXITCODE -ne 0) { Write-Error "OpenSSL decryption failed for $s"; exit $LASTEXITCODE }
  } else {
    $envPath = Join-Path $dockerDir "$s/.env"
    $outPath = Join-Path $dockerDir "$s/.env.enc"
    if (-not (Test-Path $envPath)) { Write-Host "Skipping $s (no .env)." -ForegroundColor Yellow; continue }
    if ((Test-Path $outPath) -and -not $overwriteAll) { Write-Host "Skipping $s (.env.enc exists)." -ForegroundColor Yellow; continue }
    Write-Host "Encrypting $s -> $outPath" -ForegroundColor Green
    & "$opensslExe" enc -aes-256-cbc -salt -pbkdf2 -pass "pass:$Passphrase" -in $envPath -out $outPath
    if ($LASTEXITCODE -ne 0) { Write-Error "OpenSSL encryption failed for $s"; exit $LASTEXITCODE }
    if ($deletePlain) { Remove-Item $envPath -Force; Write-Host "Deleted $envPath" -ForegroundColor DarkGray }
  }
}
if ($Mode -eq 'decrypt') {
  Write-Host "Done. Decrypted outputs were written next to stacks (or to OutputDir)." -ForegroundColor Cyan
} else {
  Write-Host "Done. Commit only the .env.enc files. Plain .env remains ignored by git." -ForegroundColor Cyan
}
