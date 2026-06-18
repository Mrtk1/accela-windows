#!/usr/bin/env pwsh
#Requires -Version 5.1

<#
.SYNOPSIS
  ACCELA Installation Script for Windows
.DESCRIPTION
  Downloads and installs ACCELA for Windows from enter-the-wired releases.
.PARAMETER InstallDir
  Custom installation directory (default: $env:LOCALAPPDATA\ACCELA)
.NOTES
  GitHub: https://github.com/ciscosweater/enter-the-wired
#>

[CmdletBinding()]
param(
    [string]$InstallDir = "$env:LOCALAPPDATA\ACCELA"
)

# Detect pipe execution (irm ... | pwsh)
$scriptPath = $PSCommandPath
$runningViaPipe = [string]::IsNullOrEmpty($scriptPath) -or $scriptPath -eq "-"

# =============================================================================
# CONFIGURATION
# =============================================================================

$GITHUB_OWNER = "ciscosweater"
$GITHUB_REPO = "enter-the-wired"

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

function Write-Status {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Type = 'Info'
    )

    $colors = @{
        'Info'    = 'Cyan'
        'Success' = 'Green'
        'Warning' = 'Yellow'
        'Error'   = 'Red'
    }

    $timestamp = Get-Date -Format "HH:mm:ss"
    Write-Host "[$timestamp] " -NoNewline -ForegroundColor DarkGray
    Write-Host $Message -ForegroundColor $colors[$Type]
}

function Expand-ZipArchive {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Destination
    )

    try {
        if (-not (Test-Path $Destination)) {
            New-Item -ItemType Directory -Path $Destination -Force | Out-Null
        }

        Expand-Archive -Path $Path -DestinationPath $Destination -Force
        return $true
    }
    catch {
        Write-Status "Error extracting archive: $_" -Type Error
        return $false
    }
}

function Get-LatestAccelaRelease {
    [CmdletBinding()]
    param()

    $apiUrl = "https://api.github.com/repos/$GITHUB_OWNER/$GITHUB_REPO/releases/latest"

    try {
        $releaseInfo = Invoke-RestMethod -Uri $apiUrl -ErrorAction Stop
        return $releaseInfo
    }
    catch {
        Write-Status "Error fetching release info: $_" -Type Error
        return $null
    }
}

function Test-DotnetInstalled {
    $dotnetExe = "$env:LOCALAPPDATA\Microsoft\dotnet\dotnet.exe"
    return (Test-Path $dotnetExe)
}

function Install-DotnetRuntime {
    Write-Status "Installing .NET Runtime..." -Type Info

    $dotnetInstallUrl = "https://builds.dotnet.microsoft.com/dotnet/scripts/v1/dotnet-install.ps1"
    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "dotnet-install-$(Get-Random)"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    try {
        $dotnetInstallScript = Join-Path $tempDir "dotnet-install.ps1"
        Write-Status "Downloading .NET install script..." -Type Info
        Invoke-WebRequest -Uri $dotnetInstallUrl -OutFile $dotnetInstallScript -UseBasicParsing

        Write-Status "Installing .NET Runtime..." -Type Info
        & $dotnetInstallScript -Channel 9.0 -Runtime dotnet

        if (Test-DotnetInstalled) {
            Write-Status ".NET Runtime installed successfully" -Type Success
        }
        else {
            Write-Status "Failed to install .NET Runtime" -Type Error
            exit 1
        }
    }
    finally {
        if (Test-Path $tempDir) {
            Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
        }
    }
}

# =============================================================================
# MAIN INSTALLATION
# =============================================================================

function Install-AccelaWindows {
    [CmdletBinding()]
    param(
        [string]$InstallDir
    )

    Write-Status "Installing ACCELA for Windows..." -Type Success
    Write-Host ""

    # Install .NET Runtime if not present
    if (-not (Test-DotnetInstalled)) {
        Install-DotnetRuntime
    }

    # Get latest release
    Write-Status "Fetching latest ACCELA release..." -Type Info
    $releaseInfo = Get-LatestAccelaRelease

    if (-not $releaseInfo) {
        Write-Status "Failed to fetch ACCELA release information" -Type Error
        exit 1
    }

    # Find Windows binary asset
    $asset = $releaseInfo.assets | Where-Object { $_.name -match "ACCELA-.*-windows-binary\.zip" }

    if (-not $asset) {
        Write-Status "No Windows binary release found" -Type Error
        Write-Status "Available assets: $($releaseInfo.assets.name -join ', ')" -Type Info
        exit 1
    }

    Write-Status "Found asset: $($asset.name)" -Type Success

    # Create temp directory
    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "accela-install-$(Get-Random)"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    try {
        $downloadPath = Join-Path $tempDir $asset.name

        # Download
        Write-Status "Downloading ACCELA..." -Type Info
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $downloadPath -ErrorAction Stop

        # Verify download
        $fileInfo = Get-Item $downloadPath
        if ($fileInfo.Length -lt 1024) {
            Write-Status "Downloaded file is too small (corrupted)" -Type Error
            exit 1
        }

        # Create install directory
        if (Test-Path $InstallDir) {
            Write-Status "Removing previous installation..." -Type Info
            Remove-Item -Recurse -Force $InstallDir -ErrorAction Stop
        }

        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

        # Extract
        Write-Status "Extracting archive..." -Type Info
        $extractDir = Join-Path $tempDir "extracted"
        New-Item -ItemType Directory -Path $extractDir -Force | Out-Null

        $success = Expand-ZipArchive -Path $downloadPath -Destination $extractDir

        if (-not $success) {
            Write-Status "Failed to extract archive" -Type Error
            exit 1
        }

        # Move contents to install directory
        $extractedItems = Get-ChildItem -Path $extractDir -Force
        foreach ($item in $extractedItems) {
            $destItem = Join-Path $InstallDir $item.Name
            if (Test-Path $destItem) {
                Remove-Item -Recurse -Force $destItem -ErrorAction SilentlyContinue
            }
            Move-Item -Path $item.FullName -Destination $destItem -ErrorAction Stop
        }

        Write-Status "ACCELA installed successfully!" -Type Success
        Write-Status "Installation directory: $InstallDir" -Type Info

        # Create desktop shortcut
        $desktopPath = [Environment]::GetFolderPath('Desktop')
        $shortcutPath = Join-Path $desktopPath "ACCELA.lnk"
        $accelaExe = Join-Path $InstallDir "ACCELA.exe"

        if (Test-Path $accelaExe) {
            Write-Status "Creating desktop shortcut..." -Type Info
            $ws = New-Object -ComObject WScript.Shell
            $shortcut = $ws.CreateShortcut($shortcutPath)
            $shortcut.TargetPath = $accelaExe
            $shortcut.WorkingDirectory = $InstallDir
            $shortcut.Description = "ACCELA"
            $shortcut.Save()
            Write-Status "Shortcut created: $shortcutPath" -Type Success
        }
        else {
            Write-Status "ACCELA.exe not found, skipping shortcut" -Type Warning
        }
    }
    finally {
        # Cleanup
        if (Test-Path $tempDir) {
            Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
        }
    }
}

# Run installation
Install-AccelaWindows -InstallDir $InstallDir
