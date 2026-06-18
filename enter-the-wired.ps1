#!/usr/bin/env pwsh
#Requires -Version 5.1

<#
.SYNOPSIS
  Enter The Wired - Combo Installer for Windows
.DESCRIPTION
  Installs ACCELA and GreenLuma on Windows systems.
  Supports both local and Invoke-Expression (curl | pwsh) execution.
.NOTES
  GitHub: https://github.com/ciscosweater/enter-the-wired
#>

[CmdletBinding()]
param()

# =============================================================================
# CONFIGURATION
# =============================================================================

$GITHUB_USER = "ciscosweater"
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

function Test-Admin {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal(
        [Security.Principal.WindowsIdentity]::GetCurrent()
    )
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-Architecture {
    $arch = (Get-CimInstance -ClassName Win32_Processor -Property Architecture).Architecture
    if ($arch -eq 9) { return 'x64' }  # AMD64
    if ($arch -eq 0) { return 'x86' }  # x86
    return 'x64'
}

function Get-OSVersion {
    return [Environment]::OSVersion.Version
}

function Test-InteractiveShell {
    return [Environment]::UserInteractive -and -not $PSISE
}

# =============================================================================
# MAIN INSTALLATION
# =============================================================================

function Install-EnterTheWiredWin {
    [CmdletBinding()]
    param()

    Write-Host ""
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host "  ENTER THE WIRED - Windows Combo Installer"
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host ""

    # Check PowerShell version
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        Write-Status "PowerShell 5.1 or higher is required. Current version: $($PSVersionTable.PSVersion)" -Type Error
        exit 1
    }

    # Detect execution method
    $scriptPath = $PSCommandPath
    $runningViaPipe = [string]::IsNullOrEmpty($scriptPath) -or $scriptPath -eq "-"

    if ($runningViaPipe) {
        Write-Status "Detected pipe execution, fetching scripts from GitHub..." -Type Success
    }

    # Get scripts directory
    if ($runningViaPipe) {
        $scriptDir = Join-Path ([System.IO.Path]::GetTempPath()) "enter-the-wired-windows-$(Get-Random)"
        New-Item -ItemType Directory -Force -Path $scriptDir | Out-Null
    }
    else {
        $scriptDir = Split-Path -Parent $scriptPath
    }

    try {
        # Fetch scripts if running via pipe
        if ($runningViaPipe) {
            $accelaUrl = "https://raw.githubusercontent.com/$GITHUB_USER/$GITHUB_REPO/main/windows/accela.ps1"
            $greenlumaUrl = "https://raw.githubusercontent.com/$GITHUB_USER/$GITHUB_REPO/main/windows/greenluma.ps1"

            Write-Status "Fetching accela.ps1..." -Type Info
            Invoke-WebRequest -Uri $accelaUrl -OutFile (Join-Path $scriptDir "accela.ps1") -ErrorAction Stop

            Write-Status "Fetching greenluma.ps1..." -Type Info
            Invoke-WebRequest -Uri $greenlumaUrl -OutFile (Join-Path $scriptDir "greenluma.ps1") -ErrorAction Stop
        }

        # Verify scripts exist
        $accelaScript = Join-Path $scriptDir "accela.ps1"
        $greenlumaScript = Join-Path $scriptDir "greenluma.ps1"

        if (-not (Test-Path $accelaScript)) {
            Write-Status "accela.ps1 not found in $scriptDir" -Type Error
            exit 1
        }

        if (-not (Test-Path $greenlumaScript)) {
            Write-Status "greenluma.ps1 not found in $scriptDir" -Type Error
            exit 1
        }

        # Dot-source the scripts
        Write-Host ""
        Write-Host "==============================================" -ForegroundColor Cyan
        Write-Host "  INSTALLING COMPONENTS"
        Write-Host "==============================================" -ForegroundColor Cyan
        Write-Host ""

        # Install ACCELA
        Write-Host "--- ACCELA ---" -ForegroundColor Magenta
        Write-Status "Installing ACCELA for Windows..." -Type Info
        . $accelaScript

        Write-Host ""

        # Install GreenLuma
        Write-Host "--- GreenLuma ---" -ForegroundColor Magenta
        Write-Status "Installing GreenLuma for Windows..." -Type Info
        . $greenlumaScript

        Write-Host ""
        Write-Host "==============================================" -ForegroundColor Cyan
        Write-Host "  ALL INSTALLATIONS COMPLETED!"
        Write-Host "==============================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  ACCELA:    Installed at %LOCALAPPDATA%\ACCELA"
        Write-Host "  GreenLuma: Installed in Steam directory"
        Write-Host ""
        Write-Host "  To use GreenLuma, restart Steam."
        Write-Host ""
        Write-Host "Protocol complete. Welcome to the Wired."
    }
    finally {
        # Cleanup temp files if running via pipe
        if ($runningViaPipe -and (Test-Path $scriptDir)) {
            Remove-Item -Recurse -Force $scriptDir -ErrorAction SilentlyContinue
        }
    }
}

# Run main installation
Install-EnterTheWiredWin @args
