#!/usr/bin/env bash
set -u

KEEP_DATA=false
FORCE=false
ADMIN_AVAILABLE=false
DISCOVERED_APPS=()
FAILED_PATHS=()

USER_DATA_PATHS=(
  "$HOME/Library/Application Support/Docker Desktop"
  "$HOME/Library/Caches/com.docker.docker"
  "$HOME/Library/Containers/com.docker.docker"
  "$HOME/Library/Group Containers/group.com.docker"
  "$HOME/Library/HTTPStorages/com.docker.docker"
  "$HOME/Library/Logs/Docker Desktop"
  "$HOME/Library/Preferences/com.docker.docker.plist"
  "$HOME/Library/Preferences/com.docker.docker.helper.plist"
  "$HOME/Library/Preferences/com.electron.docker-Desktop.plist"
  "$HOME/Library/Preferences/com.electron.docker-Desktop.helper.plist"
  "$HOME/Library/Saved Application State/com.electron.docker-Desktop.savedState"
)

SYSTEM_PATHS=(
  "/Library/PrivilegedHelperTools/com.docker.vmnetd"
  "/Library/PrivilegedHelperTools/com.docker.socket"
  "/Library/LaunchDaemons/com.docker.vmnetd.plist"
  "/Library/LaunchDaemons/com.docker.socket.plist"
)

usage() {
  echo "Usage: $(basename "$0") [--keep-data] [--force]"
  echo ""
  echo "  --keep-data   Preserve Docker data and configuration files"
  echo "  --force       Skip confirmation, cleanup, and restart prompts"
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

append_unique_app() {
  local candidate="$1"
  local existing

  for existing in "${DISCOVERED_APPS[@]}"; do
    if [[ "$existing" == "$candidate" ]]; then
      return
    fi
  done

  DISCOVERED_APPS+=("$candidate")
}

discover_docker_apps() {
  local candidate
  local standard_paths=(
    "/Applications/Docker.app"
    "$HOME/Applications/Docker.app"
  )

  for candidate in "${standard_paths[@]}"; do
    if [[ -d "$candidate" ]]; then
      append_unique_app "$candidate"
    fi
  done

  if command -v mdfind >/dev/null 2>&1; then
    while IFS= read -r candidate; do
      if [[ -d "$candidate" ]]; then
        append_unique_app "$candidate"
      fi
    done < <(mdfind 'kMDItemCFBundleIdentifier == "com.docker.docker"' 2>/dev/null)
  fi
}

has_docker_artifacts() {
  local path

  if (( ${#DISCOVERED_APPS[@]} > 0 )); then
    return 0
  fi

  for path in "${SYSTEM_PATHS[@]}" "${USER_DATA_PATHS[@]}"; do
    if [[ -e "$path" || -L "$path" ]]; then
      return 0
    fi
  done

  return 1
}

requires_administrator() {
  local app_path
  local path

  for app_path in "${DISCOVERED_APPS[@]}"; do
    if [[ "$app_path" == /Applications/* ]]; then
      return 0
    fi
  done

  for path in "${SYSTEM_PATHS[@]}"; do
    if [[ -e "$path" || -L "$path" ]]; then
      return 0
    fi
  done

  return 1
}

request_administrator() {
  if [[ "$EUID" -eq 0 ]]; then
    ADMIN_AVAILABLE=true
    return 0
  fi

  echo "Administrator privileges are required for system-wide Docker components."
  echo "Requesting administrator access..."
  if sudo -v; then
    ADMIN_AVAILABLE=true
    return 0
  fi

  echo "Administrator access was not granted; user-owned files will still be removed." >&2
  return 1
}

run_privileged() {
  if [[ "$EUID" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

remove_path() {
  local path="$1"
  local label="$2"
  local needs_admin="${3:-false}"

  if [[ ! -e "$path" && ! -L "$path" ]]; then
    return 0
  fi

  echo "Removing $label..."
  if [[ "$needs_admin" == true ]]; then
    if [[ "$ADMIN_AVAILABLE" != true ]] || ! run_privileged rm -rf -- "$path"; then
      echo "Could not remove $label due to permissions or files in use: $path" >&2
      FAILED_PATHS+=("$path")
      return 1
    fi
  elif ! rm -rf -- "$path"; then
    echo "Could not remove $label due to permissions or files in use: $path" >&2
    FAILED_PATHS+=("$path")
    return 1
  fi

  echo "Successfully removed $label"
  return 0
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
  pkill -f "/Docker.app/" 2>/dev/null || true
  sleep 2
}

run_bundled_uninstaller() {
  local app_path="$1"
  local uninstaller="$app_path/Contents/MacOS/uninstall"
  local needs_admin=false

  if [[ "$KEEP_DATA" == true || ! -x "$uninstaller" ]]; then
    return 1
  fi

  if [[ "$app_path" == /Applications/* ]]; then
    needs_admin=true
  fi

  echo "Attempting the bundled Docker Desktop uninstaller..."
  if [[ "$needs_admin" == true ]]; then
    if [[ "$ADMIN_AVAILABLE" != true ]] || ! run_privileged "$uninstaller"; then
      echo "Bundled uninstaller failed; continuing with manual removal." >&2
      return 1
    fi
  elif ! "$uninstaller"; then
    echo "Bundled uninstaller failed; continuing with manual removal." >&2
    return 1
  fi

  echo "Bundled Docker Desktop uninstall completed."
  return 0
}

unload_launch_services() {
  local path

  for path in /Library/LaunchDaemons/com.docker.*.plist; do
    if [[ -e "$path" && "$ADMIN_AVAILABLE" == true ]]; then
      run_privileged launchctl bootout system "$path" >/dev/null 2>&1 || true
    fi
  done

  for path in "$HOME/Library/LaunchAgents"/com.docker*.plist "$HOME/Library/LaunchAgents"/com.electron.docker*.plist; do
    if [[ -e "$path" ]]; then
      launchctl bootout "gui/$UID" "$path" >/dev/null 2>&1 || true
    fi
  done
}

remove_startup_entries() {
  local path

  echo "Removing Docker Desktop startup entries..."
  unload_launch_services

  for path in "$HOME/Library/LaunchAgents"/com.docker*.plist "$HOME/Library/LaunchAgents"/com.electron.docker*.plist; do
    remove_path "$path" "Docker launch agent" false || true
  done

  if command -v osascript >/dev/null 2>&1; then
    osascript <<'APPLESCRIPT' >/dev/null 2>&1 || echo "Could not remove one or more Docker login items." >&2
tell application "System Events"
  repeat with itemName in {"Docker", "Docker Desktop"}
    if exists login item itemName then delete login item itemName
  end repeat
end tell
APPLESCRIPT
  fi
}

remove_package_receipts() {
  local receipt

  if ! command -v pkgutil >/dev/null 2>&1; then
    return
  fi

  while IFS= read -r receipt; do
    case "$receipt" in
      com.docker.docker|com.docker.pkg|com.docker.desktop)
        if [[ "$ADMIN_AVAILABLE" == true ]]; then
          run_privileged pkgutil --forget "$receipt" >/dev/null 2>&1 \
            && echo "Removed package receipt: $receipt" \
            || echo "Failed to remove package receipt: $receipt" >&2
        fi
        ;;
    esac
  done < <(pkgutil --pkgs 2>/dev/null)
}

remove_installation_components() {
  local app_path
  local path
  local needs_admin

  for app_path in "${DISCOVERED_APPS[@]}"; do
    needs_admin=false
    if [[ "$app_path" == /Applications/* ]]; then
      needs_admin=true
    fi
    remove_path "$app_path" "Docker Desktop app ($app_path)" "$needs_admin" || true
  done

  for path in "${SYSTEM_PATHS[@]}"; do
    remove_path "$path" "Docker system component" true || true
  done

  remove_startup_entries
  remove_package_receipts
}

remove_user_data() {
  local path

  if [[ "$KEEP_DATA" == true ]]; then
    echo "Keeping Docker data and configuration files."
    return
  fi

  for path in "${USER_DATA_PATHS[@]}"; do
    remove_path "$path" "Docker data or configuration" false || true
  done
}

prompt_yes_no() {
  local prompt="$1"
  local answer=""

  printf '%s [y/N] ' "$prompt"
  read -r answer
  [[ "$answer" =~ ^[Yy]$ ]]
}

main() {
  local app_path

  echo "Docker Desktop Uninstaller for macOS"
  echo "======================================"
  echo ""
  echo "Checking for Docker Desktop installations..."

  discover_docker_apps
  if ! has_docker_artifacts; then
    echo "Docker Desktop does not appear to be installed."
    exit 0
  fi

  for app_path in "${DISCOVERED_APPS[@]}"; do
    echo "Found: $app_path"
  done
  if (( ${#DISCOVERED_APPS[@]} == 0 )); then
    echo "Found Docker Desktop support files from an incomplete or previous installation."
  fi

  if requires_administrator; then
    request_administrator || true
  fi

  if [[ "$FORCE" != true ]] && ! prompt_yes_no "Proceed with uninstallation?"; then
    echo "Uninstall cancelled."
    exit 0
  fi

  echo ""
  echo "Starting Docker Desktop uninstallation..."
  stop_docker_processes

  for app_path in "${DISCOVERED_APPS[@]}"; do
    run_bundled_uninstaller "$app_path" && break
  done

  remove_installation_components
  remove_user_data

  echo ""
  echo "======================================"
  echo "Docker Desktop uninstall process completed."
  echo "======================================"

  if (( ${#FAILED_PATHS[@]} > 0 )); then
    echo ""
    echo "Additional manual cleanup may be needed for:"
    printf '  - %s\n' "${FAILED_PATHS[@]}"
  fi
  if [[ "$KEEP_DATA" == true ]]; then
    echo "Docker data and configuration were preserved under $HOME/Library."
  fi
  echo "Restart the Mac for changes to take full effect."

  if [[ "$FORCE" != true ]]; then
    if prompt_yes_no "Would you like to retry the additional cleanup now?"; then
      remove_installation_components
      remove_user_data
    fi

    if prompt_yes_no "Would you like to restart your Mac now?"; then
      echo "Restarting your Mac..."
      if [[ "$ADMIN_AVAILABLE" != true ]]; then
        request_administrator || return 1
      fi
      run_privileged shutdown -r now
    fi
  fi
}

shopt -s nullglob
main
