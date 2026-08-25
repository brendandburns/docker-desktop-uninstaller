# Uninstall Docker Desktop for Windows
# Handles both global and local installations
# Administrator privileges only required for global installations

param(
    [switch]$KeepData,  # Keep Docker data if specified
    [switch]$Force      # Force uninstall without prompts
)

# Function to check if running as administrator
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Function to elevate to administrator
function Invoke-AdminElevation {
    $scriptPath = $MyInvocation.ScriptName
    $scriptArgs = $MyInvocation.UnboundArguments
    
    Write-Host "Administrator privileges required for global Docker installation." -ForegroundColor Yellow
    Write-Host "Requesting elevation..." -ForegroundColor Yellow
    
    $argString = if ($scriptArgs) { $scriptArgs -join ' ' } else { '' }
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" $argString" -Verb RunAs
    exit 0
}

Write-Host "Docker Desktop Uninstaller for Windows" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Define installation paths
$globalPath = "C:\Program Files\Docker\Docker"
$localPath = "$env:LOCALAPPDATA\Docker"
$dockerDataPath = "$env:LOCALAPPDATA\Docker\wsl"
$dockerConfigPath = "$env:APPDATA\Docker"

# Function to check if path exists
function Test-InstallationPath {
    param([string]$Path)
    if (Test-Path $Path) {
        Write-Host "Found: $Path" -ForegroundColor Green
        return $true
    }
    return $false
}

# Function to uninstall via Programs and Features
function Uninstall-ViaWMI {
    param([string]$ProductName)
    
    try {
        Write-Host "Attempting to uninstall '$ProductName' via WMI..." -ForegroundColor Yellow
        $app = Get-WmiObject -Class Win32_Product -Filter "Name='$ProductName'"
        
        if ($app) {
            $app.Uninstall() | Out-Null
            Write-Host "Successfully uninstalled $ProductName" -ForegroundColor Green
            return $true
        }
        return $false
    }
    catch {
        Write-Host "WMI uninstall failed: $_" -ForegroundColor Red
        return $false
    }
}

# Function to uninstall via msiexec
function Uninstall-ViaMSI {
    try {
        Write-Host "Attempting to uninstall via msiexec..." -ForegroundColor Yellow
        
        # Find Docker Desktop MSI in registry
        $regPath = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall"
        $dockerKey = Get-ChildItem $regPath | Where-Object {
            $_.GetValue("DisplayName") -like "*Docker Desktop*"
        }
        
        if ($dockerKey) {
            $uninstallString = $dockerKey.GetValue("UninstallString")
            if ($uninstallString) {
                Write-Host "Found uninstall string: $uninstallString"
                cmd /c "$uninstallString /quiet"
                Start-Sleep -Seconds 3
                Write-Host "MSI uninstall completed" -ForegroundColor Green
                return $true
            }
        }
        return $false
    }
    catch {
        Write-Host "MSI uninstall failed: $_" -ForegroundColor Red
        return $false
    }
}

# Function to remove directory
function Remove-DockerDirectory {
    param([string]$Path, [string]$Description)

    try {
        if (Test-Path $Path -ErrorAction Stop) {
            Write-Host "Removing $Description..." -ForegroundColor Yellow
            Remove-Item -Path $Path -Recurse -Force -ErrorAction Stop
            Write-Host "Successfully removed $Description" -ForegroundColor Green
            return $true
        }

        return $true
    }
    catch {
        Write-Host "Could not remove $Description due to permissions or files in use: $Path" -ForegroundColor Yellow
        Write-Host "  $($_.Exception.Message)" -ForegroundColor DarkYellow
        return $false
    }
}

# Function to remove Docker uninstall entries from Windows Registry
function Remove-DockerUninstallKeys {
    $uninstallHives = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    )

    foreach ($hive in $uninstallHives) {
        if (-not (Test-Path $hive)) {
            continue
        }

        $matches = Get-ChildItem -Path $hive -ErrorAction SilentlyContinue | Where-Object {
            $displayName = $_.GetValue("DisplayName")
            $uninstallString = $_.GetValue("UninstallString")

            ($displayName -match "Docker Desktop|Docker Desktop Installer|Docker Desktop for Windows") -or 
            ($uninstallString -match "Docker Desktop|Docker Desktop Installer|docker desktop")
        }

        foreach ($match in $matches) {
            try {
                Remove-Item -Path $match.PSPath -Recurse -Force -ErrorAction Stop
                Write-Host "Removed uninstall registry key: $($match.Name)" -ForegroundColor Green
            }
            catch {
                Write-Host "Failed to remove uninstall registry key: $($match.Name) - $_" -ForegroundColor Yellow
            }
        }
    }
}

# Function to remove Docker Desktop from Windows startup apps
function Remove-DockerStartupEntries {
    $startupRegistryPaths = @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run",
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run",
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32"
    )

    foreach ($regPath in $startupRegistryPaths) {
        if (-not (Test-Path $regPath)) {
            continue
        }

        $properties = (Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue).PSObject.Properties |
            Where-Object {
                $_.Name -notmatch '^PS' -and
                ($_.Name -match '^Docker Desktop$|com\.docker' -or [string]$_.Value -match 'Docker Desktop|com\.docker')
            }

        foreach ($property in $properties) {
            try {
                Remove-ItemProperty -Path $regPath -Name $property.Name -Force -ErrorAction Stop
                Write-Host "Removed startup registry entry: $($property.Name)" -ForegroundColor Green
            }
            catch {
                Write-Host "Failed to remove startup registry entry: $($property.Name) - $_" -ForegroundColor Yellow
            }
        }
    }

    $startupFolders = @(
        [Environment]::GetFolderPath('Startup'),
        [Environment]::GetFolderPath('CommonStartup')
    ) | Where-Object { $_ }

    foreach ($startupFolder in $startupFolders) {
        Get-ChildItem -Path $startupFolder -File -ErrorAction SilentlyContinue | Where-Object {
            $_.BaseName -match '^Docker Desktop$|com\.docker'
        } | ForEach-Object {
            try {
                Remove-Item -Path $_.FullName -Force -ErrorAction Stop
                Write-Host "Removed startup shortcut: $($_.FullName)" -ForegroundColor Green
            }
            catch {
                Write-Host "Failed to remove startup shortcut: $($_.FullName) - $_" -ForegroundColor Yellow
            }
        }
    }
}

# Function to clean registry entries
function Clean-RegistryEntries {
    Write-Host "Cleaning registry entries..." -ForegroundColor Yellow
    
    try {
        # Remove standard Docker registry keys
        $regPaths = @(
            "HKCU:\Software\Docker",
            "HKCU:\Software\Classes\Docker*",
            "HKLM:\Software\Docker"
        )
        
        foreach ($regPath in $regPaths) {
            if (Test-Path $regPath) {
                Remove-Item -Path $regPath -Recurse -Force -ErrorAction SilentlyContinue
                Write-Host "Removed registry key: $regPath" -ForegroundColor Green
            }
        }

        # Remove Docker uninstall entries from the Windows app registration hive
        Remove-DockerUninstallKeys

        # Remove Docker Desktop from Windows startup apps
        Remove-DockerStartupEntries
    }
    catch {
        Write-Host "Registry cleanup encountered issues: $_" -ForegroundColor Yellow
    }
}

# Main uninstall logic
Write-Host "Checking for Docker Desktop installations..." -ForegroundColor Cyan
Write-Host ""

$globalFound = Test-InstallationPath $globalPath
$localFound = Test-InstallationPath $localPath

# Check if admin privileges are needed
if ($globalFound -and -not (Test-Administrator)) {
    Invoke-AdminElevation
}

if (-not $globalFound -and -not $localFound) {
    Write-Host "Docker Desktop does not appear to be installed." -ForegroundColor Yellow
    exit 0
}

Write-Host ""

if (-not $Force) {
    $continue = Read-Host "Proceed with uninstallation? (Y/N)"
    if ($continue -ne "Y" -and $continue -ne "y") {
        Write-Host "Uninstall cancelled." -ForegroundColor Yellow
        exit 0
    }
}

Write-Host ""
Write-Host "Starting Docker Desktop uninstallation..." -ForegroundColor Cyan
Write-Host ""

# Stop Docker services
Write-Host "Stopping Docker services..." -ForegroundColor Yellow
Stop-Service -Name "Docker" -ErrorAction SilentlyContinue -Force
Stop-Service -Name "com.docker.service" -ErrorAction SilentlyContinue -Force
Start-Sleep -Seconds 2

# Attempt uninstall via WMI and MSI
$uninstalled = $false
$uninstalled = $uninstalled -or (Uninstall-ViaWMI "Docker Desktop")
$uninstalled = $uninstalled -or (Uninstall-ViaMSI)

if (-not $uninstalled) {
    Write-Host "Could not uninstall via standard methods, attempting manual removal..." -ForegroundColor Yellow
}

Write-Host ""

# Remove installation directories
Remove-DockerDirectory $globalPath "Global Docker installation (Program Files)"
Remove-DockerDirectory $localPath "Local Docker installation (AppData)"

# Remove Docker data unless specified to keep
if (-not $KeepData) {
    Remove-DockerDirectory $dockerDataPath "Docker WSL data"
    Remove-DockerDirectory $dockerConfigPath "Docker configuration"
}
else {
    Write-Host "Keeping Docker data at: $dockerDataPath" -ForegroundColor Cyan
    Write-Host "Keeping Docker config at: $dockerConfigPath" -ForegroundColor Cyan
}

Write-Host ""

# Clean registry
Clean-RegistryEntries

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Docker Desktop uninstall process completed!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Additional manual cleanup (if needed):" -ForegroundColor Yellow
if ($globalFound) {
    Write-Host "  - Remove C:\Program Files\Docker directory"
}
Write-Host "  - Remove $env:LOCALAPPDATA\Docker directory"
if (-not $KeepData) {
    Write-Host "  - Remove $env:APPDATA\Docker directory"
}
Write-Host "  - Restart your computer for changes to take full effect"
Write-Host ""

if (-not $Force) {
    $runManualCleanup = Read-Host "Would you like to run the additional directory cleanup now? (Y/N)"
    if ($runManualCleanup -eq "Y" -or $runManualCleanup -eq "y") {
        if ($globalFound) {
            Remove-DockerDirectory "C:\Program Files\Docker" "remaining global Docker files"
        }
        Remove-DockerDirectory $localPath "remaining local Docker files"

        if (-not $KeepData) {
            Remove-DockerDirectory $dockerConfigPath "remaining Docker configuration"
        }
    }

    $restartComputer = Read-Host "Would you like to restart your computer now? (Y/N)"
    if ($restartComputer -eq "Y" -or $restartComputer -eq "y") {
        Write-Host "Restarting your computer..." -ForegroundColor Yellow
        Restart-Computer
    }
}
