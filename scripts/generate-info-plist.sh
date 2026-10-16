#!/usr/bin/env bash
set -euo pipefail

# Generate bundle metadata without modifying the checked-in plist.
[[ $# -eq 3 ]] || { echo 'Usage: generate-info-plist.sh VERSION TEMPLATE OUTPUT' >&2; exit 1; }
version_file="$1"
template_file="$2"
output_file="$3"
app_version="$(cat "$version_file")"
[[ "$app_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'error: VERSION must contain a numeric X.Y.Z version.' >&2; exit 1; }

mkdir -p "$(dirname "$output_file")"
/usr/bin/plutil -replace CFBundleShortVersionString -string "$app_version" -o "$output_file" "$template_file"
