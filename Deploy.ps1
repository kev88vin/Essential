
# ==========================================
# Winget Deployment Script
# Repairs Winget -> Downloads Lists -> Removes -> Installs
# ==========================================

$InstallListUrl = "https://raw.githubusercontent.com/kev88vin/Essential/Essential/install.txt"

$RemoveListUrl  = "https://raw.githubusercontent.com/kev88vin/Essential/Essential/remove.txt"

$TempFolder = "$env:TEMP\WingetDeploy"
$InstallFile = Join-Path $TempFolder "install.txt"
$RemoveFile  = Join-Path $TempFolder "remove.txt"
$LogFile     = Join-Path $TempFolder "winget-deploy.log"

New-Item -ItemType Directory -Path $TempFolder -Force | Out-Null

function Write-Log {
    param([string]$Message)

    $Entry = "{0} - {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message

    Write-Host $Entry
    Add-Content -Path $LogFile -Value $Entry
}

function Repair-Winget {

    Write-Log "Starting Winget repair process..."

    #
    # Verify App Installer package
    #
    $AppInstaller = Get-AppxPackage Microsoft.DesktopAppInstaller -AllUsers -ErrorAction SilentlyContinue

    if (-not $AppInstaller) {
        Write-Log "Microsoft.DesktopAppInstaller not installed."
        Write-Log "Install from Microsoft Store:"
        Write-Log "https://apps.microsoft.com/detail/9NBLGGH4NNS1"
        return $false
    }

    #
    # Re-register App Installer
    #
    try {

        Write-Log "Re-registering Microsoft.DesktopAppInstaller..."

        Add-AppxPackage `
            -DisableDevelopmentMode `
            -Register "$($AppInstaller.InstallLocation)\AppXManifest.xml" `
            -ErrorAction Stop

        Write-Log "App Installer registration completed."
    }
    catch {
        Write-Log "App Installer registration failed: $_"
    }

    #
    # Re-register VCLibs
    #
    try {

        Write-Log "Repairing Microsoft.VCLibs..."

        Get-AppxPackage Microsoft.VCLibs* -AllUsers |
        ForEach-Object {

            Add-AppxPackage `
                -DisableDevelopmentMode `
                -Register "$($_.InstallLocation)\AppXManifest.xml" `
                -ErrorAction SilentlyContinue
        }

        Write-Log "Microsoft.VCLibs repair completed."
    }
    catch {
        Write-Log "VCLibs repair failed: $_"
    }

    #
    # Re-register UI.Xaml
    #
    try {

        Write-Log "Repairing Microsoft.UI.Xaml..."

        Get-AppxPackage Microsoft.UI.Xaml* -AllUsers |
        ForEach-Object {

            Add-AppxPackage `
                -DisableDevelopmentMode `
                -Register "$($_.InstallLocation)\AppXManifest.xml" `
                -ErrorAction SilentlyContinue
        }

        Write-Log "Microsoft.UI.Xaml repair completed."
    }
    catch {
        Write-Log "UI.Xaml repair failed: $_"
    }

    #
    # Verify Winget executable
    #
    try {

        $Version = winget --version

        Write-Log "Winget detected: $Version"

    }
    catch {

        Write-Log "Winget executable unavailable after repair."
        return $false
    }

    #
    # Repair sources
    #
    try {

        Write-Log "Resetting Winget sources..."

        winget source reset --force | Out-Null
        winget source update | Out-Null

        Write-Log "Winget sources updated."
    }
    catch {
        Write-Log "Source repair failed: $_"
    }

    #
    # Functional test
    #
    try {

        winget search Microsoft.PowerToys `
            --accept-source-agreements | Out-Null

        Write-Log "Winget functional test passed."

        return $true
    }
    catch {

        Write-Log "Winget functional test failed."

        return $false
    }
}

# ==========================================
# Verify / Repair Winget
# ==========================================

Write-Log "Checking Winget..."

$WingetHealthy = $false

try {

    winget --version | Out-Null

    Write-Log "Winget found."

    $WingetHealthy = $true
}
catch {

    Write-Log "Winget missing or broken."
}

if (-not $WingetHealthy) {

    if (-not (Repair-Winget)) {

        Write-Log "Winget repair failed. Exiting."
        exit 1
    }
}

# Always repair sources even if Winget is healthy
try {

    winget source reset --force | Out-Null
    winget source update | Out-Null

}
catch {

    Write-Log "Source refresh warning: $_"
}

# ==========================================
# Download Lists
# ==========================================

Write-Log "Downloading package lists..."

try {

    Invoke-WebRequest `
        -Uri $InstallListUrl `
        -OutFile $InstallFile `
        -UseBasicParsing

    Invoke-WebRequest `
        -Uri $RemoveListUrl `
        -OutFile $RemoveFile `
        -UseBasicParsing

    Write-Log "Package lists downloaded."
}
catch {

    Write-Log "Failed downloading package lists: $_"
    exit 1
}

# ==========================================
# Uninstall Packages
# ==========================================

if (Test-Path $RemoveFile) {

    Write-Log "Processing uninstall list..."

    Get-Content $RemoveFile |
    Where-Object {
        $_.Trim() -ne "" -and
        -not $_.StartsWith("#")
    } |
    ForEach-Object {

        $Package = $_.Trim()

        Write-Log "Removing: $Package"

        winget uninstall `
            --id $Package `
            --exact `
            --silent `
            --accept-source-agreements

        if ($LASTEXITCODE -eq 0) {
            Write-Log "Removed: $Package"
        }
        else {
            Write-Log "Removal skipped or failed: $Package"
        }
    }
}

# ==========================================
# Install Packages
# ==========================================

Write-Log "Processing install list..."

Get-Content $InstallFile |
Where-Object {
    $_.Trim() -ne "" -and
    -not $_.StartsWith("#")
} |
ForEach-Object {

    $Package = $_.Trim()

    Write-Log "Installing: $Package"

    winget install `
        --id $Package `
        --exact `
        --silent `
        --accept-package-agreements `
        --accept-source-agreements

    if ($LASTEXITCODE -eq 0) {
        Write-Log "Installed: $Package"
    }
    else {
        Write-Log "Install failed: $Package"
    }
}

Write-Log "Deployment completed successfully."
Write-Log "Log file: $LogFile"
