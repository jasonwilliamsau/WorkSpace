#!/bin/sh
set -eu

package_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
product_name="EDGE Work Dashboard"
source_app="${package_root}/.build/app/${product_name}.app"
applications_dir="${HOME}/Applications"
installed_app="${applications_dir}/${product_name}.app"

"${package_root}/Scripts/build-app.sh"
codesign --verify --deep --strict --verbose=2 "$source_app"

mkdir -p "$applications_dir"
pkill -x EdgeWorkDashboard >/dev/null 2>&1 || true
ditto "$source_app" "$installed_app"
codesign --verify --deep --strict --verbose=2 "$installed_app"

launch_attempt=1
while ! open "$installed_app"; do
  if [ "$launch_attempt" -ge 3 ]; then
    printf 'Installed successfully, but macOS could not relaunch the app. Open it from ~/Applications.\n' >&2
    exit 1
  fi
  launch_attempt=$((launch_attempt + 1))
  sleep 1
done

printf 'Installed and launched:\n  %s\n' "$installed_app"
