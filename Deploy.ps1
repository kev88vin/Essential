# ==========================================
# Winget Deployment Script
# ==========================================

$InstallListUrl = "https://raw.githubusercontent.com/kev88vin/Essential/Essential/install.txt"

$RemoveListUrl  = "https://raw.githubusercontent.com/kev88vin/Essential/Essential/remove.txt"

$TempFolder = "$env:TEMP\WingetDeploy"
$InstallFile = "$TempFolder\install.txt"
$RemoveFile  = "$TempFolder\remove.txt"
$LogFile     = "$TempFolder\winget-deploy.log"

New-Item -ItemType Directory -Path $TempFolder -Force | Out-Null

function Write-Log {
    param([string]$Message)

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Entry = "$Timestamp - $Message"

    Write-Host $Entry
    Add-Content -Path $LogFile -Value $Entry
}

# ==========================================
# Verify Winget
# ==========================================

Write-Log "Checking Winget installation..."

try {
    $WingetVersion = winget --version
    Write-Log "Winget found: $WingetVersion"
}
catch {
    Write-Log "Winget not found."

    Write-Host ""
    Write-Host "Install App Installer from Microsoft Store:"
    Write-Host "https://apps.microsoft.com/detail/9NBLGGH4NNS1"
    exit 1
}

# ==========================================
# Repair Winget Sources
# ==========================================

Write-Log "Resetting Winget sources..."

try {
    winget source reset --force
    winget source update
    Write-Log "Winget sources repaired."
}
catch {
    Write-Log "Source repair failed: $_"
}

# ==========================================
# Check App Installer Package
# ==========================================

Write-Log "Checking App Installer package..."

$AppInstaller = Get-AppxPackage Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue

if (-not $AppInstaller) {
    Write-Log "Microsoft.DesktopAppInstaller missing."
    Write-Log "Install App Installer from Microsoft Store."
    exit 1
}
else {
    Write-Log "App Installer OK"
}

# ==========================================
# Download Lists
# ==========================================

Write-Log "Downloading package lists..."

Invoke-WebRequest `
    -Uri $InstallListUrl `
    -OutFile $InstallFile `
    -UseBasicParsing

Invoke-WebRequest `
    -Uri $RemoveListUrl `
    -OutFile $RemoveFile `
    -UseBasicParsing

Write-Log "Lists downloaded."

# ==========================================
# Uninstall Packages
# ==========================================

if (Test-Path $RemoveFile) {

    Write-Log "Processing removals..."

    Get-Content $RemoveFile |
        Where-Object {
            $_ -and $_.Trim() -ne "" -and -not $_.StartsWith("#")
        } |
        ForEach-Object {

            $Package = $_.Trim()

            Write-Log "Removing $Package"

            winget uninstall `
                --id $Package `
                --exact `
                --silent `
                --accept-source-agreements

            if ($LASTEXITCODE -eq 0) {
                Write-Log "Removed $Package"
            }
            else {
                Write-Log "Removal failed or package not found: $Package"
            }
        }
}

# ==========================================
# Install Packages
# ==========================================

Write-Log "Processing installs..."

Get-Content $InstallFile |
    Where-Object {
        $_ -and $_.Trim() -ne "" -and -not $_.StartsWith("#")
    } |
    ForEach-Object {

        $Package = $_.Trim()

        Write-Log "Installing $Package"

        winget install `
            --id $Package `
            --exact `
            --silent `
            --accept-package-agreements `
            --accept-source-agreements

        if ($LASTEXITCODE -eq 0) {
            Write-Log "Installed $Package"
        }
        else {
            Write-Log "Install failed: $Package"
        }
    }

Write-Log "Deployment complete."
Write-Log "Log file: $LogFile"
