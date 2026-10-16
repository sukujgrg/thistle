#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  --help|-h)
    echo 'Usage: scripts/build.sh [--help]'
    echo 'Build and install an Apple Silicon app into ~/Applications.'
    echo 'Use make release to sign, notarize, and publish a distribution release.'
    exit 0
    ;;
esac
[[ $# -eq 0 ]] || { echo "Unknown argument: $1" >&2; exit 1; }

cd "$(dirname "$0")/.."
install_dir="${APP_INSTALL_DIR:-$HOME/Applications}"
make app BUILD_CONFIGURATION=release SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
mkdir -p "$install_dir"
destination="$install_dir/Thistle.app"
if [[ -L "$destination" ]]; then
  echo "Refusing to replace a symlink: $destination" >&2
  exit 1
fi
rm -rf "$destination"
ditto bin/Thistle.app "$destination"
echo "Built $destination"
