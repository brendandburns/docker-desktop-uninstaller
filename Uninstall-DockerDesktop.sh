#!/usr/bin/env bash
set -u

KEEP_DATA=false
FORCE=false

usage() {
  echo "Usage: $(basename "$0") [--keep-data] [--force]"
  echo ""
  echo "  --keep-data   Preserve Docker data and configuration files"
  echo "  --force       Skip the confirmation prompt"
  echo "  -h, --help    Show this help message"
}

for arg in "$@"; do
  case "$arg" in
    --keep-data)
      KEEP_DATA=true
      ;;
    --force)
      FORCE=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      usage >&2
      exit 1
      ;;
  esac
done

run_as_root() {
  if [[ "$EUID" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

remove_if_exists() {
  local path="$1"
  local label="$2"

  if [[ -e "$path" || -L "$path" ]]; then
    run_as_root rm -rf -- "$path"
    echo "Removed $label: $path"
  fi
}

stop_docker_processes() {
  echo "Stopping Docker Desktop processes..."

  if command -v osascript >/dev/null 2>&1; then
    osascript -e 'try' -e 'tell application "Docker" to quit' -e 'end try' 2>/dev/null || true
    osascript -e 'try' -e 'tell application "Docker Desktop" to quit' -e 'end try' 2>/dev/null || true
  fi

  killall "Docker" 2>/dev/null || true
  killall "Docker Desktop" 2>/dev/null || true
  pkill -f "Docker Desktop" 2>/dev/null || true
  pkill -f "/Applications/Docker.app" 2>/dev/null || true

  sleep 2
}

main() {
  local app_candidates=(
    "/Applications/Docker.app"
    "$HOME/Applications/Docker.app"
  )

  local app_path=""
  for candidate in "${app_candidates[@]}"; do
    if [[ -d "$candidate" ]]; then
      app_path="$candidate"
      break
    fi
  done

  if [[ -z "$app_path" ]]; then
    echo "Docker Desktop does not appear to be installed."
    exit 0
  fi

  echo "Found Docker Desktop: $app_path"

  if [[ "$FORCE" != true ]]; then
    echo "Proceed with uninstallation? [y/N]"
    read -r answer
    if [[ ! "$answer" =~ ^[Yy]$ ]]; then
      echo "Uninstall cancelled."
      exit 0
    fi
  fi

  echo "Starting Docker Desktop uninstallation..."
  stop_docker_processes

  remove_if_exists "$app_path" "Docker Desktop app"

  if [[ "$KEEP_DATA" != true ]]; then
    remove_if_exists "$HOME/Library/Application Support/Docker Desktop" "Docker Desktop app support"
    remove_if_exists "$HOME/Library/Containers/com.docker.docker" "Docker container data"
    remove_if_exists "$HOME/Library/Group Containers/group.com.docker" "Docker group container data"
    remove_if_exists "$HOME/Library/Logs/Docker Desktop" "Docker Desktop logs"
    remove_if_exists "$HOME/Library/Preferences/com.docker.docker.plist" "Docker preferences"
    remove_if_exists "$HOME/Library/Preferences/com.docker.docker.helper.plist" "Docker helper preferences"
    remove_if_exists "$HOME/Library/Preferences/com.electron.docker-Desktop.plist" "Docker Desktop Electron preferences"
    remove_if_exists "$HOME/Library/Preferences/com.electron.docker-Desktop.helper.plist" "Docker Desktop helper preferences"

    remove_if_exists "/Library/PrivilegedHelperTools/com.docker.vmnetd" "Docker VMNet privileged helper"
    remove_if_exists "/Library/LaunchDaemons/com.docker.vmnetd.plist" "Docker VMNet launch daemon"
    remove_if_exists "/Library/LaunchDaemons/com.docker.socket.plist" "Docker socket launch daemon"
  else
    echo "Keeping Docker data and app support files."
  fi

  echo ""
  echo "Docker Desktop uninstall process completed."
  echo "If needed, restart the Mac to fully clear any remaining system state."
}

main "$@"
