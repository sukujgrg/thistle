#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./scripts/release-notarize-distribute.sh --notary-profile PROFILE [options]

Required:
  --notary-profile PROFILE   notarytool keychain profile name.

Optional:
  --version VERSION          Release version (default: Git tag, else VERSION file)
  --build-number NUMBER      Build number (default: tag +BUILD suffix, else Info.plist CFBundleVersion)
  --skip-version-file-check  Do not require VERSION file to match release version.
  --output-dir DIR           Output directory (default: build/release)
  --team-id TEAM_ID          Apple Developer Team ID (default: from Developer ID identity)
  --signing-identity NAME    Developer ID Application identity (default: first in keychain)

GitHub distribution:
  --github                   Upload artifacts to GitHub release using gh CLI.
  --repo OWNER/REPO          GitHub repository slug. Required when --github is set if origin cannot be derived.
  --tag TAG                  Git tag for the release (default: exact tag at HEAD, else v<VERSION>)
  --notes FILE               Release notes file path for gh release create.
EOF
}

fail() {
  echo "error: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

ensure_developer_id_identity() {
  local identities
  identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"

  if [[ -n "$SIGNING_IDENTITY" ]]; then
    if ! grep -F "Developer ID Application:" <<< "$identities" | grep -F "$SIGNING_IDENTITY" >/dev/null; then
      fail "Developer ID Application signing identity '$SIGNING_IDENTITY' was not found in the active keychain. Install the certificate and private key, then verify with: security find-identity -v -p codesigning"
    fi
    return 0
  fi

  if ! grep -F "Developer ID Application:" <<< "$identities" >/dev/null; then
    fail "No Developer ID Application signing identity found in the active keychain. Install the certificate and private key from Apple Developer, then verify with: security find-identity -v -p codesigning"
  fi
}

resolve_signing_identity() {
  if [[ -n "$SIGNING_IDENTITY" ]]; then
    return 0
  fi

  local identities line
  identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  line="$(grep -F "Developer ID Application:" <<< "$identities" | head -1)"
  if [[ "$line" =~ \"(Developer ID Application: [^\"]+)\" ]]; then
    SIGNING_IDENTITY="${BASH_REMATCH[1]}"
  else
    fail "Unable to parse a Developer ID Application identity from the keychain."
  fi
}

resolve_export_team_id() {
  if [[ -n "$TEAM_ID" ]]; then
    return 0
  fi

  if [[ "$SIGNING_IDENTITY" =~ \(([A-Z0-9]{10})\) ]]; then
    TEAM_ID="${BASH_REMATCH[1]}"
    return 0
  fi

  local identities developer_id_line
  identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  developer_id_line="$(grep -F "Developer ID Application:" <<< "$identities" | head -1)"
  if [[ "$developer_id_line" =~ \(([A-Z0-9]{10})\) ]]; then
    TEAM_ID="${BASH_REMATCH[1]}"
  fi
}

OUTPUT_DIR="build/release"
APP_BUNDLE="bin/Thistle.app"
NOTARY_PROFILE=""
TEAM_ID=""
SIGNING_IDENTITY=""
VERSION=""
BUILD_NUMBER=""
PUBLISH_GITHUB=false
REPO=""
TAG=""
NOTES_FILE=""
SKIP_VERSION_FILE_CHECK=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="$2"
      shift 2
      ;;
    --build-number)
      BUILD_NUMBER="$2"
      shift 2
      ;;
    --skip-version-file-check)
      SKIP_VERSION_FILE_CHECK=true
      shift
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --notary-profile)
      NOTARY_PROFILE="$2"
      shift 2
      ;;
    --team-id)
      TEAM_ID="$2"
      shift 2
      ;;
    --signing-identity)
      SIGNING_IDENTITY="$2"
      shift 2
      ;;
    --github)
      PUBLISH_GITHUB=true
      shift
      ;;
    --repo)
      REPO="$2"
      shift 2
      ;;
    --tag)
      TAG="$2"
      shift 2
      ;;
    --notes)
      NOTES_FILE="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

derive_repo_from_origin() {
  local origin_url
  origin_url="$(git config --get remote.origin.url 2>/dev/null || true)"
  [[ -n "$origin_url" ]] || return 1

  if [[ "$origin_url" =~ ^https://github.com/([^/]+/[^/.]+)(\.git)?$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi

  if [[ "$origin_url" =~ ^git@github.com:([^/]+/[^/.]+)(\.git)?$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi

  return 1
}

derive_version_from_tag() {
  local tag="$1"
  local normalized_tag="${tag#refs/tags/}"
  normalized_tag="${normalized_tag#v}"
  local version_part="${normalized_tag%%+*}"

  if [[ "$version_part" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
    printf '%s' "$version_part"
    return 0
  fi

  return 1
}

derive_build_from_tag() {
  local tag="$1"
  local normalized_tag="${tag#refs/tags/}"
  normalized_tag="${normalized_tag#v}"

  if [[ "$normalized_tag" =~ \+([0-9]+)$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi

  return 1
}

find_exact_head_tag() {
  command -v git >/dev/null 2>&1 || return 1
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  git describe --tags --exact-match 2>/dev/null || return 1
}

ensure_clean_git_state() {
  command -v git >/dev/null 2>&1 || return 0
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0

  if [[ -n "$(git status --porcelain)" ]]; then
    fail "Working tree is dirty. Commit or stash changes before creating a release."
  fi
}

ensure_no_pending_pushes() {
  command -v git >/dev/null 2>&1 || return 0
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0

  local upstream
  upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
  [[ -n "$upstream" ]] || fail "Current branch has no upstream. Push the branch and set upstream before releasing."

  local counts behind ahead
  counts="$(git rev-list --left-right --count "${upstream}...HEAD" 2>/dev/null || true)"
  [[ -n "$counts" ]] || fail "Unable to compare HEAD with upstream '$upstream'."
  read -r behind ahead <<< "$counts"
  [[ -n "$ahead" ]] || fail "Unable to parse upstream comparison for '$upstream'."

  if [[ "$ahead" != "0" ]]; then
    fail "Current branch is ahead of upstream by $ahead commit(s). Push before releasing."
  fi
}

ensure_remote_tag_exists() {
  local tag="$1"
  command -v git >/dev/null 2>&1 || fail "git is required to verify GitHub release tags."
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "GitHub release requires a Git repository."

  git rev-parse -q --verify "refs/tags/$tag" >/dev/null 2>&1 \
    || fail "Tag '$tag' does not exist locally. Create and push it before running release-github."

  git ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null 2>&1 \
    || fail "Tag '$tag' does not exist on origin. Push it before running release-github."
}

if [[ -z "$NOTARY_PROFILE" ]]; then
  fail "--notary-profile is required"
fi

if [[ -n "$TAG" ]]; then
  TAG_VERSION="$(derive_version_from_tag "$TAG" || true)"
  [[ -n "$TAG_VERSION" ]] || fail "Tag '$TAG' is not a valid release tag. Use vX.Y.Z or vX.Y.Z+BUILD."

  if [[ -n "$VERSION" && "$VERSION" != "$TAG_VERSION" ]]; then
    fail "--version ($VERSION) does not match --tag ($TAG => $TAG_VERSION)"
  fi
  VERSION="$TAG_VERSION"
fi

if [[ -z "$VERSION" ]]; then
  HEAD_TAG="$(find_exact_head_tag || true)"
  if [[ -n "$HEAD_TAG" ]]; then
    TAG="$HEAD_TAG"
    VERSION="$(derive_version_from_tag "$HEAD_TAG" || true)"
  fi

  if [[ -z "$VERSION" && -f VERSION ]]; then
    VERSION="$(tr -d '[:space:]' < VERSION)"
  fi

  [[ -n "$VERSION" ]] || fail "Unable to determine version. Pass --version, add a VERSION file, or create a Git tag like vX.Y.Z."
fi

ensure_clean_git_state
ensure_no_pending_pushes

if [[ "$PUBLISH_GITHUB" == true ]]; then
  if [[ -z "$REPO" ]]; then
    REPO="$(derive_repo_from_origin || true)"
  fi
  [[ -n "$REPO" ]] || fail "--repo OWNER/REPO is required when --github is set (or configure an origin remote)"
  if [[ -z "$TAG" ]]; then
    TAG="$(find_exact_head_tag || true)"
  fi
  [[ -n "$TAG" ]] || fail "GitHub release requires an existing Git tag at HEAD. Create and push a tag like v$VERSION first."
  ensure_remote_tag_exists "$TAG"
fi

if [[ -z "$BUILD_NUMBER" && -n "$TAG" ]]; then
  BUILD_NUMBER="$(derive_build_from_tag "$TAG" || true)"
fi

if [[ -z "$BUILD_NUMBER" ]]; then
  BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Info.plist 2>/dev/null || true)"
fi

if [[ -n "$BUILD_NUMBER" && ! "$BUILD_NUMBER" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
  fail "--build-number must be numeric or dot-separated numeric."
fi

if [[ "$SKIP_VERSION_FILE_CHECK" == false && -f VERSION ]]; then
  VERSION_FILE_VALUE="$(tr -d '[:space:]' < VERSION)"
  [[ -n "$VERSION_FILE_VALUE" ]] || fail "VERSION file is empty. Set it to $VERSION."
  [[ "$VERSION_FILE_VALUE" == "$VERSION" ]] || fail "VERSION file ($VERSION_FILE_VALUE) does not match release version ($VERSION). Update VERSION first or use --skip-version-file-check."
fi

require_command make
require_command xcrun
require_command ditto
require_command shasum
require_command security
require_command codesign

ensure_developer_id_identity
resolve_signing_identity
resolve_export_team_id

if [[ "$PUBLISH_GITHUB" == true ]]; then
  require_command gh
fi

TMP_DIR="$(mktemp -d "${TMPDIR%/}/thistleRelease.XXXXXX")"
NOTARY_JSON="$TMP_DIR/notary-result.json"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

echo "==> Building ($VERSION)"
make clean
make BUILD_CONFIGURATION=release build
mkdir -p "$OUTPUT_DIR"

[[ -d "$APP_BUNDLE" ]] || fail "Expected app bundle at $APP_BUNDLE"

APP_PATH="$APP_BUNDLE"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_PATH/Contents/Info.plist"
if [[ -n "$BUILD_NUMBER" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_PATH/Contents/Info.plist"
fi

echo "==> Signing with $SIGNING_IDENTITY"
codesign --force --options runtime --timestamp \
  --sign "$SIGNING_IDENTITY" \
  --entitlements ThistleEngine.entitlements \
  "$APP_PATH/Contents/MacOS/ThistleEngine"
codesign --force --options runtime --timestamp \
  --sign "$SIGNING_IDENTITY" \
  "$APP_PATH/Contents/MacOS/ThistleUpdater"
codesign --force --options runtime --timestamp \
  --sign "$SIGNING_IDENTITY" \
  --entitlements ThistleMacOS.entitlements \
  "$APP_PATH/Contents/MacOS/Thistle"
codesign --force --options runtime --timestamp \
  --sign "$SIGNING_IDENTITY" \
  --entitlements ThistleMacOS.entitlements \
  "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

APP_NAME="$(basename "$APP_PATH" .app)"
NOTARIZE_ZIP="$TMP_DIR/$APP_NAME-$VERSION-notary.zip"
FINAL_ZIP="$OUTPUT_DIR/$APP_NAME-$VERSION-notarized.zip"
FINAL_SHA="$FINAL_ZIP.sha256"
FINAL_APP="$OUTPUT_DIR/$APP_NAME.app"

echo "==> Creating zip for notarization"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$NOTARIZE_ZIP"

echo "==> Submitting for notarization"
xcrun notarytool submit "$NOTARIZE_ZIP" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait \
  --output-format json > "$NOTARY_JSON"

if ! grep -q '"status"[[:space:]]*:[[:space:]]*"Accepted"' "$NOTARY_JSON"; then
  echo "Notarization response:"
  cat "$NOTARY_JSON"
  fail "Notarization did not return Accepted status."
fi

echo "==> Stapling app"
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

echo "==> Preparing distributable artifacts"
mkdir -p "$OUTPUT_DIR"
rm -rf "$FINAL_APP"
cp -R "$APP_PATH" "$FINAL_APP"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$FINAL_ZIP"
shasum -a 256 "$FINAL_ZIP" > "$FINAL_SHA"

if [[ "$PUBLISH_GITHUB" == true ]]; then
  echo "==> Publishing to GitHub release: $REPO ($TAG)"
  if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    gh release upload "$TAG" "$FINAL_ZIP" "$FINAL_SHA" --repo "$REPO" --clobber
  else
    CREATE_ARGS=(
      gh release create "$TAG" "$FINAL_ZIP" "$FINAL_SHA"
      --repo "$REPO"
      --title "$APP_NAME $VERSION"
    )
    if [[ -n "$NOTES_FILE" ]]; then
      CREATE_ARGS+=(--notes-file "$NOTES_FILE")
    else
      CREATE_ARGS+=(--notes "Automated notarized release $VERSION")
    fi
    "${CREATE_ARGS[@]}"
  fi
fi

echo
echo "Release complete."
echo "App: $FINAL_APP"
echo "Zip: $FINAL_ZIP"
echo "SHA: $FINAL_SHA"
