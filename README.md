# Usage

### Windows
```pwsh
.\Test-DockerDesktop.ps1
.\Uninstall-DockerDesktop.ps1 [-KeepData] [-Force]
```

### macOS
```bash
chmod +x test-docker-desktop.sh uninstall-docker-desktop.sh
./test-docker-desktop.sh
./uninstall-docker-desktop.sh [--keep-data] [--force]
```

The uninstallers remove Docker Desktop application files, startup entries, and
system registration. Use `-KeepData` or `--keep-data` to preserve Docker data
and configuration, and `-Force` or `--force` to skip interactive prompts.
