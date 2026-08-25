#!/usr/bin/env bash

has_docker_desktop() {
  local app_paths=(
    "/Applications/Docker.app"
    "$HOME/Applications/Docker.app"
  )

  for path in "${app_paths[@]}"; do
    if [[ -d "$path" ]]; then
      local version=""
      if [[ -f "$path/Contents/Info.plist" ]]; then
        version=$( /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$path/Contents/Info.plist" 2>/dev/null || true )
      fi

      if [[ -n "$version" ]]; then
        echo "Docker Desktop is installed. Version: $version"
      else
        echo "Docker Desktop is installed."
      fi
      return 0
    fi
  done

  echo "Docker Desktop is NOT installed."
  return 1
}

has_docker_desktop
