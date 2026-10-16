#!/bin/bash
set -euo pipefail

app_path="${1:?Pass the app bundle path}"
signing_identity="${2:-}"

if [[ -z "$signing_identity" ]]; then
  identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  # Prefer the distribution identity so local runs retain the released app's identity.
  for kind in "Developer ID Application" "Apple Development"; do
    signing_identity="$(awk -F '"' -v kind="$kind: " 'index($2, kind) == 1 { print $2; exit }' <<< "$identities")"
    [[ -z "$signing_identity" ]] || break
  done
fi

if [[ -z "$signing_identity" || "$signing_identity" == "-" ]]; then
  signing_identity="-"
  echo "No Apple signing identity selected; using ad-hoc signing. Local Network permission may not survive a rebuild. Set SIGNING_IDENTITY to an Apple-issued identity for reliable local-network access." >&2
fi

echo "Signing local app with $signing_identity"
codesign --force --sign "$signing_identity" --identifier dev.thistle.engine \
  --entitlements ThistleEngine.entitlements "$app_path/Contents/MacOS/ThistleEngine"
codesign --force --sign "$signing_identity" --identifier dev.thistle.updater \
  "$app_path/Contents/MacOS/ThistleUpdater"
codesign --force --sign "$signing_identity" --identifier dev.thistle \
  --entitlements ThistleMacOS.entitlements "$app_path/Contents/MacOS/Thistle"
codesign --force --sign "$signing_identity" --identifier dev.thistle \
  --entitlements ThistleMacOS.entitlements "$app_path"
codesign --verify --deep --strict "$app_path"
