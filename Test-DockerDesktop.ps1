function Test-DockerDesktopInstalled {
    # Registry locations for installed applications
    $registryPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    foreach ($path in $registryPaths) {
        $docker = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue |
            Where-Object {
                $_.DisplayName -like "Docker Desktop*"
            }

        if ($docker) {
            return [PSCustomObject]@{
                Installed = $true
                Version   = $docker.DisplayVersion
                Source    = "Registry"
            }
        }
    }

    # Default installation path
    $exePath = Join-Path $Env:ProgramFiles "Docker\Docker\Docker Desktop.exe"

    if (Test-Path $exePath) {
        $version = (Get-Item $exePath).VersionInfo.ProductVersion

        return [PSCustomObject]@{
            Installed = $true
            Version   = $version
            Source    = "Executable"
        }
    }

    return [PSCustomObject]@{
        Installed = $false
        Version   = $null
        Source    = $null
    }
}

$result = Test-DockerDesktopInstalled

if ($result.Installed) {
    Write-Host "Docker Desktop is installed. Version: $($result.Version)"
}
else {
    Write-Host "Docker Desktop is NOT installed."
}