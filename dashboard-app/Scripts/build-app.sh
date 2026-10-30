#!/bin/sh
set -eu

package_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
product_name="EDGE Work Dashboard"
executable_name="EdgeWorkDashboard"
output_dir="${package_root}/.build/app"
app_path="${output_dir}/${product_name}.app"
codesign_identity="${CODESIGN_IDENTITY:--}"

swift build \
  -c release \
  --package-path "$package_root" \
  -Xswiftc -warnings-as-errors

rm -rf "$app_path"
mkdir -p \
  "${app_path}/Contents/MacOS" \
  "${app_path}/Contents/Resources/Dashboard"

install -m 755 \
  "${package_root}/.build/release/${executable_name}" \
  "${app_path}/Contents/MacOS/${executable_name}"
install -m 644 \
  "${package_root}/Resources/Info.plist" \
  "${app_path}/Contents/Info.plist"
ditto \
  "${package_root}/Sources/EdgeWorkDashboard/Resources/Dashboard" \
  "${app_path}/Contents/Resources/Dashboard"

codesign \
  --force \
  --deep \
  --sign "$codesign_identity" \
  --identifier com.nocreativity.EdgeWorkDashboard \
  "$app_path"
codesign --verify --deep --strict --verbose=2 "$app_path"

printf '%s\n' "$app_path"
