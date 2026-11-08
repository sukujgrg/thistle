#!/bin/bash
# Build the linux/arm64 vsock→TCP forwarder into the app Resources tree.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
src="$root/guest-forwarder/vsock-tcp-forward.c"
out_dir="${1:-$root/Resources/guest-forwarder/linux-arm64}"
out="$out_dir/vsock-tcp-forward"

mkdir -p "$out_dir"

if [[ ! -f "$src" ]]; then
  echo "missing $src" >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required to build the guest forwarder (linux/arm64)." >&2
  exit 1
fi

echo "Building guest forwarder -> $out"
docker run --rm --platform linux/arm64 \
  -v "$root/guest-forwarder:/src:ro" \
  -v "$out_dir:/out" \
  debian:bookworm-slim \
  bash -lc '
    set -euo pipefail
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq gcc libc6-dev >/dev/null
    gcc -O2 -static -pthread -o /out/vsock-tcp-forward /src/vsock-tcp-forward.c
  '

chmod +x "$out"
file "$out"
echo "guest forwarder ready"
