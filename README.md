# Usage

[![CI](https://github.com/brendandburns/docker-desktop-uninstaller/actions/workflows/ci.yml/badge.svg)](https://github.com/brendandburns/docker-desktop-uninstaller/actions/workflows/ci.yml)
[![E2E](https://github.com/brendandburns/docker-desktop-uninstaller/actions/workflows/e2e.yml/badge.svg)](https://github.com/brendandburns/docker-desktop-uninstaller/actions/workflows/e2e.yml)

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

## CI and releases

GitHub Actions parses and analyzes the PowerShell scripts on Windows and checks
the Bash scripts with Bash and ShellCheck on macOS. The detector scripts and the
macOS uninstaller help command are also smoke tested without removing software.

Push a tag beginning with `v` (for example, `v1.0.0`) to create a GitHub release
containing `.zip` and `.tar.gz` archives plus SHA-256 checksums.

The E2E workflow runs only when started manually. It invokes the platform test
scripts in `e2e`, which download and install Docker Desktop, verify that the
detector finds it, run the uninstaller, and verify that Docker Desktop is no
longer present.

Windows E2E testing is available as a manual workflow option. It requires a
disposable, self-hosted Windows 10 or 11 x64 runner with the custom label
`docker-desktop-e2e`. GitHub-hosted Windows runners use Windows Server, which
Docker Desktop does not support. Do not use a workstation that contains Docker
data you need to keep because the test performs a full uninstall.

## Run E2E locally

E2E tests are destructive and require a clean test machine with Docker Desktop
absent. The macOS test requires administrator access through `sudo`. The Windows
test requires Windows 10 or 11 but uses Docker Desktop's per-user installation
mode and does not require an elevated PowerShell session.

### Windows

```pwsh
.\e2e\Test-DockerDesktopE2E.ps1
```

### macOS

```bash
bash e2e/test-macos.sh
```

Both tests download the current Docker Desktop installer, perform the complete
install and uninstall cycle, and clean up an installation they created if the
test fails. Set `DOCKER_DESKTOP_URL` on macOS or pass `-DockerDesktopUrl` on
Windows to test a specific installer.
