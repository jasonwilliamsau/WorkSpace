#!/bin/sh
set -eu

repository_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

swift test \
  --package-path "${repository_root}/touch-driver" \
  -Xswiftc -warnings-as-errors

swift test \
  --package-path "${repository_root}/dashboard-app" \
  -Xswiftc -warnings-as-errors
