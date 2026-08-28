[CmdletBinding()]
param(
    [string]$DockerDesktopUrl = "https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$detector = Join-Path $repoRoot "Test-DockerDesktop.ps1"
$uninstaller = Join-Path $repoRoot "Uninstall-DockerDesktop.ps1"
$workDirectory = Join-Path ([System.IO.Path]::GetTempPath()) "docker-desktop-e2e-$PID"
$installer = Join-Path $workDirectory "Docker Desktop Installer.exe"
$installedByTest = $false

function Get-DockerDesktopStatus {
    $output = & $detector | Out-String
    Write-Host $output
    return $output
}

$operatingSystem = Get-CimInstance Win32_OperatingSystem
if ($operatingSystem.ProductType -ne 1) {
    throw "Docker Desktop requires Windows 10 or 11, not Windows Server."
}

$initialStatus = Get-DockerDesktopStatus
if ($initialStatus -notmatch "Docker Desktop is NOT installed\.") {
    throw "Docker Desktop must not be installed before the E2E test starts."
}

New-Item -ItemType Directory -Path $workDirectory | Out-Null

try {
    Write-Host "Downloading Docker Desktop..."
    Invoke-WebRequest -Uri $DockerDesktopUrl -OutFile $installer

    Write-Host "Installing Docker Desktop..."
    $installedByTest = $true
    $installProcess = Start-Process `
        -FilePath $installer `
        -ArgumentList "install", "--user", "--quiet", "--accept-license", "--no-windows-containers" `
        -Wait `
        -PassThru
    if ($installProcess.ExitCode -ne 0) {
        throw "Docker Desktop installer exited with code $($installProcess.ExitCode)."
    }

    $installedStatus = Get-DockerDesktopStatus
    if ($installedStatus -notmatch "Docker Desktop is installed\.") {
        throw "The detector did not find the Docker Desktop installation."
    }

    Write-Host "Uninstalling Docker Desktop..."
    & $uninstaller -Force

    $finalStatus = Get-DockerDesktopStatus
    if ($finalStatus -notmatch "Docker Desktop is NOT installed\.") {
        throw "Docker Desktop is still detected after uninstallation."
    }
    if (Test-Path "$env:LOCALAPPDATA\Programs\DockerDesktop") {
        throw "The Docker Desktop installation directory still exists."
    }

    $installedByTest = $false
    Write-Host "Docker Desktop E2E test passed."
}
finally {
    if ($installedByTest -and (Test-Path $installer)) {
        Write-Host "Cleaning up Docker Desktop after the test..."
        Start-Process -FilePath $installer -ArgumentList "uninstall", "--quiet" -Wait
    }
    Remove-Item -Path $workDirectory -Recurse -Force -ErrorAction SilentlyContinue
}