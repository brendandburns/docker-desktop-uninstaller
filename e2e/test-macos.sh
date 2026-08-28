#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/.." && pwd)
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/docker-desktop-e2e.XXXXXX")
dmg_path="$work_dir/Docker.dmg"
mount_point="$work_dir/mount"
mounted=false
installed_by_test=false

case "$(uname -m)" in
  arm64) architecture=arm64 ;;
  x86_64) architecture=amd64 ;;
  *)
    echo "Unsupported macOS architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

docker_desktop_url=${DOCKER_DESKTOP_URL:-"https://desktop.docker.com/mac/main/$architecture/Docker.dmg"}

cleanup() {
  local status=$?
  trap - EXIT

  if [[ "$mounted" == true ]]; then
    hdiutil detach "$mount_point" >/dev/null 2>&1 || hdiutil detach "$mount_point" -force >/dev/null 2>&1 || true
  fi

  if [[ "$installed_by_test" == true && -d /Applications/Docker.app ]]; then
    echo "Cleaning up Docker Desktop after the test..."
    sudo /Applications/Docker.app/Contents/MacOS/uninstall >/dev/null 2>&1 || true
    sudo rm -rf /Applications/Docker.app
  fi

  rm -rf "$work_dir"
  exit "$status"
}
trap cleanup EXIT

if [[ "$(uname -s)" != Darwin ]]; then
  echo "This E2E test requires macOS." >&2
  exit 1
fi

set +e
initial_output=$(bash "$repo_root/test-docker-desktop.sh" 2>&1)
initial_status=$?
set -e
printf '%s\n' "$initial_output"
if [[ "$initial_status" -ne 1 ]] || ! grep -Fq "Docker Desktop is NOT installed." <<<"$initial_output"; then
  echo "Docker Desktop must not be installed before the E2E test starts." >&2
  exit 1
fi

echo "Downloading Docker Desktop..."
curl --fail --location --retry 3 --output "$dmg_path" "$docker_desktop_url"

echo "Installing Docker Desktop..."
mkdir "$mount_point"
hdiutil attach "$dmg_path" -nobrowse -mountpoint "$mount_point"
mounted=true
installed_by_test=true
sudo "$mount_point/Docker.app/Contents/MacOS/install" --accept-license
hdiutil detach "$mount_point"
mounted=false

installed_output=$(bash "$repo_root/test-docker-desktop.sh")
printf '%s\n' "$installed_output"
grep -Fq "Docker Desktop is installed." <<<"$installed_output"

echo "Uninstalling Docker Desktop..."
bash "$repo_root/uninstall-docker-desktop.sh" --force

set +e
final_output=$(bash "$repo_root/test-docker-desktop.sh" 2>&1)
final_status=$?
set -e
printf '%s\n' "$final_output"
test "$final_status" -eq 1
grep -Fq "Docker Desktop is NOT installed." <<<"$final_output"
test ! -d /Applications/Docker.app

installed_by_test=false
echo "Docker Desktop E2E test passed."