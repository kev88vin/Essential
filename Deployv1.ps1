# ==========================================
# Winget Deployment Script
# ==========================================

$InstallListUrl = "https://raw.githubusercontent.com/YOURORG/YOURREPO/main/install.txt"
$RemoveListUrl  = "https://raw.githubusercontent.com/YOURORG/YOURREPO/main/remove.txt"

function Write-Log {
    param([string]$Message)

    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$TimeStamp - $Message"
}

function Reset-WingetSources {

    Write-Log "Resetting Winget sources..."

    try {
        winget upgrade --all
        winget source reset --force
        winget source update

        Write-Log "Winget sources reset successfully."
        return $true
    }
    catch {

        Write-Log "Winget source reset failed: $_"
        return $false
    }
}

function Repair-Winget {

    Write-Log "Starting Winget repair..."

    #
    # First attempt source repair
    #
    Reset-WingetSources | Out-Null

    #
    # Verify App Installer exists
    #
    $AppInstaller = Get-AppxPackage Microsoft.DesktopAppInstaller -AllUsers -ErrorAction SilentlyContinue

    if (-not $AppInstaller) {

        Write-Log "Microsoft.DesktopAppInstaller not found."
        Write-Log "Install App Installer from Microsoft Store."
        return $false
    }

    #
    # Re-register App Installer
    #
    try {

        Add-AppxPackage `
            -DisableDevelopmentMode `
            -Register "$($AppInstaller.InstallLocation)\AppXManifest.xml"

        Write-Log "App Installer repaired."
    }
    catch {

        Write-Log "App Installer repair failed: $_"
    }

    #
    # Repair dependencies
    #
    Get-AppxPackage Microsoft.VCLibs* -AllUsers |
    ForEach-Object {

        try {
            Add-AppxPackage `
                -DisableDevelopmentMode `
                -Register "$($_.InstallLocation)\AppXManifest.xml"
        }
        catch {}
    }

    Get-AppxPackage Microsoft.UI.Xaml* -AllUsers |
    ForEach-Object {

        try {
            Add-AppxPackage `
                -DisableDevelopmentMode `
                -Register "$($_.InstallLocation)\AppXManifest.xml"
        }
        catch {}
    }

    #
    # Reset sources again after repairs
    #
    Reset-WingetSources | Out-Null

    #
    # Validate Winget
    #
    try {

        winget --version | Out-Null
        winget source list | Out-Null
        winget search Microsoft.PowerToys --accept-source-agreements | Out-Null

        Write-Log "Winget repair completed successfully."
        return $true
    }
    catch {

        Write-Log "Winget validation failed."
        return $false
    }
}

# ==========================================
# Initial Source Reset
# ==========================================

Reset-WingetSources | Out-Null

# ==========================================
# Verify Winget
# ==========================================

$WingetHealthy = $false

try {

    winget --version | Out-Null
    winget source list | Out-Null

    Write-Log "Winget detected."

    $WingetHealthy = $true
}
catch {

    Write-Log "Winget check failed."
}

# ==========================================
# Repair if Necessary
# ==========================================

if (-not $WingetHealthy) {

    if (-not (Repair-Winget)) {

        Write-Log "Winget repair failed."
        exit 1
    }
}

# ==========================================
# Final Source Reset
# ==========================================

Reset-WingetSources | Out-Null

# ==========================================
# Download Package Lists
# ==========================================

$TempFolder = Join-Path $env:TEMP "WingetDeploy"

New-Item `
    -Path $TempFolder `
    -ItemType Directory `
    -Force | Out-Null

$InstallFile = Join-Path $TempFolder "install.txt"
$RemoveFile  = Join-Path $TempFolder "remove.txt"

Invoke-WebRequest `
    -Uri $InstallListUrl `
    -OutFile $InstallFile

Invoke-WebRequest `
    -Uri $RemoveListUrl `
    -OutFile $RemoveFile

# ==========================================
# Process Removals
# ==========================================

if (Test-Path $RemoveFile) {

    Get-Content $RemoveFile |
    Where-Object {
        $_.Trim() -and
        -not $_.StartsWith('#')
    } |
    ForEach-Object {

        $Package = $_.Trim()

        Write-Log "Removing $Package"

        winget uninstall `
            --id $Package `
            --exact `
            --silent `
            --accept-source-agreements
    }
}

# ==========================================
# Process Installs
# ==========================================

Get-Content $InstallFile |
Where-Object {
    $_.Trim() -and
    -not $_.StartsWith('#')
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
}

# ==========================================
# Final Validation
# ==========================================

Write-Log "Running final validation..."

winget source list
winget list

Write-Log "Deployment complete."
