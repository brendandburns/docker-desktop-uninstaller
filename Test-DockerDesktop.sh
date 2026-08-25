#!/usr/bin/env bash

find_docker_desktop() {
  local app_path
  local app_paths=(
    "/Applications/Docker.app"
    "$HOME/Applications/Docker.app"
  )

  for app_path in "${app_paths[@]}"; do
    if [[ -d "$app_path" ]]; then
      printf '%s\n' "$app_path"
      return 0
    fi
  done

  if command -v mdfind >/dev/null 2>&1; then
    while IFS= read -r app_path; do
      if [[ -d "$app_path" ]]; then
        printf '%s\n' "$app_path"
        return 0
      fi
    done < <(mdfind 'kMDItemCFBundleIdentifier == "com.docker.docker"' 2>/dev/null)
  fi

  return 1
}

test_docker_desktop_installed() {
  local app_path
  local version=""

  if ! app_path=$(find_docker_desktop); then
    echo "Docker Desktop is NOT installed."
    return 1
  fi

  if [[ -f "$app_path/Contents/Info.plist" ]]; then
    version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app_path/Contents/Info.plist" 2>/dev/null || true)
  fi

  echo "Docker Desktop is installed. Version: $version"
}

test_docker_desktop_installed
