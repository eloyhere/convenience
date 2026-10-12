# ============================================================
#  Git User Information Configuration + SSH Key Generation + Trusted Hosts Configuration + Connection Test
#  When saving, please select "UTF-8 with BOM" encoding
# ============================================================

$userName  = Read-Host "Please enter your Git username"
$userEmail = Read-Host "Please enter your Git email address"
$passphrase = Read-Host "Please enter your SSH key passphrase (leave blank for no passphrase, press Enter directly)"

if ([string]::IsNullOrWhiteSpace($userName) -or [string]::IsNullOrWhiteSpace($userEmail)) {
    Write-Host "Username or email address cannot be empty. Script terminated." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

# --- Configure Git global user information ---
git config --global user.name  "$userName"
git config --global user.email "$userEmail"

Write-Host "Git user information has been configured:" -ForegroundColor Green
Write-Host "  Username: $userName"
Write-Host "  Email address: $userEmail"
if ([string]::IsNullOrEmpty($passphrase)) {
    Write-Host "  Key passphrase: (none)" -ForegroundColor Gray
} else {
    Write-Host "  Key passphrase: (set)" -ForegroundColor Gray
}
Write-Host ""

# --- Generate SSH key ---
$sshKeyPath = "$env:USERPROFILE\.ssh\id_ed25519"

if (Test-Path "$sshKeyPath.pub") {
    Write-Host "SSH key already exists, skipping generation." -ForegroundColor Yellow
} else {
    # Ensure the .ssh directory exists
    if (-not (Test-Path "$env:USERPROFILE\.ssh")) {
        New-Item -ItemType Directory -Path "$env:USERPROFILE\.ssh" -Force | Out-Null
    }

    # PowerShell treats an empty string "" as "no argument" and discards it,
    # so an empty passphrase must be passed as '""' to ssh-keygen, otherwise it will report "option requires an argument -- N"
    if ([string]::IsNullOrEmpty($passphrase)) {
        $passArg = '""'
    } else {
        $passArg = $passphrase
    }

    ssh-keygen -t ed25519 -C "$userEmail" -f "$sshKeyPath" -N $passArg

    if ($LASTEXITCODE -eq 0) {
        Write-Host "SSH key has been generated." -ForegroundColor Green
    } else {
        Write-Host "SSH key generation failed. Please check manually." -ForegroundColor Red
        Read-Host "Press Enter to exit"
        exit 1
    }
}

# --- Copy public key to clipboard ---
Get-Content "$sshKeyPath.pub" | Set-Clipboard
Write-Host ""
Write-Host "Public key has been copied to the clipboard!" -ForegroundColor Green
Write-Host "Please add the public key to platforms such as GitHub/GitLab:" -ForegroundColor Cyan
Write-Host "  GitHub: Settings -> SSH and GPG keys -> New SSH key"
Write-Host "  GitLab: Settings -> SSH Keys"
Write-Host ""
Write-Host "Public key content preview:" -ForegroundColor Cyan
Get-Content "$sshKeyPath.pub"
Write-Host ""

# --- Trusted hosts configuration + connection test ---
$testHost = Read-Host "If you have already configured the public key on the target website, please enter the website address (e.g. github.com); leave blank to skip"

if (-not [string]::IsNullOrWhiteSpace($testHost)) {
    $testHost = $testHost.Trim()

    # Remove any protocol prefix and path that may be present
    $testHost = $testHost -replace '^https?://', '' -replace '/.*$', ''

    $sshDir     = "$env:USERPROFILE\.ssh"
    $knownHosts = "$sshDir\known_hosts"

    if (-not (Test-Path $sshDir)) {
        New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
    }
    if (-not (Test-Path $knownHosts)) {
        New-Item -ItemType File -Path $knownHosts -Force | Out-Null
    }

    Write-Host ""
    Write-Host "Retrieving SSH public key for $testHost..." -ForegroundColor Cyan
    $scanOutput = ssh-keyscan -t ed25519,rsa $testHost 2>$null

    if ($scanOutput) {
        # Remove old records for this host to avoid conflicts, then add new records
        ssh-keygen -R $testHost -f $knownHosts 2>$null | Out-Null
        $scanOutput | Add-Content -Path $knownHosts
        Write-Host "$testHost has been added to the trusted hosts." -ForegroundColor Green
    } else {
        Write-Host "Unable to retrieve the SSH public key for $testHost. Please check your network or whether the domain name is correct." -ForegroundColor Red
        Write-Host "Skipping the subsequent connection test." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Press Enter to exit..." -ForegroundColor Yellow
        Read-Host
        exit 1
    }

    Write-Host ""
    Write-Host "Testing SSH connection to $testHost..." -ForegroundColor Cyan

    # -o BatchMode=yes: avoids getting stuck on passphrase/confirmation prompts
    $testResult = ssh -T -o BatchMode=yes "git@$testHost" 2>&1
    $testOutput = ($testResult | Out-String).Trim()

    # GitHub returns exit code 1 on success, so we cannot rely solely on the exit code; we must check the output text
    if ($testOutput -match "successfully authenticated|Welcome to GitLab|Hi [^!]+!") {
        Write-Host "Test successful!" -ForegroundColor Green
        Write-Host $testOutput -ForegroundColor Gray
    } else {
        Write-Host "Test failed. Output below:" -ForegroundColor Red
        Write-Host $testOutput -ForegroundColor Gray
        Write-Host ""
        Write-Host "Possible causes:" -ForegroundColor Yellow

        switch -Regex ($testOutput) {
            "Permission denied" {
                Write-Host "  · The public key has not been added to $testHost, or the key being used does not match the one on the website." -ForegroundColor Yellow
            }
            "Host key verification failed" {
                Write-Host "  · Host key verification failed. The known_hosts file may be corrupted or missing." -ForegroundColor Yellow
            }
            "Could not resolve hostname|Name or service not known" {
                Write-Host "  · The domain name could not be resolved. Please check whether the website address is spelled correctly." -ForegroundColor Yellow
            }
            "Connection timed out|Connection refused|Network is unreachable" {
                Write-Host "  · Unable to connect to $testHost. Please check your network, proxy, or firewall settings." -ForegroundColor Yellow
            }
            default {
                Write-Host "  · Unknown error. Please investigate further based on the output above." -ForegroundColor Yellow
            }
        }
    }
}

Write-Host ""
Write-Host "Press Enter to exit..." -ForegroundColor Yellow
Read-Host