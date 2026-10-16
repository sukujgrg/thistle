#!/usr/bin/env bash
set -euo pipefail

[[ $# -eq 1 && "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Usage: set-version.sh X.Y.Z' >&2; exit 1; }
cd "$(dirname "$0")/.."
printf '%s\n' "$1" > VERSION
