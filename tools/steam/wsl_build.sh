#!/usr/bin/env bash
# Runs inside WSL so Mac and Linux builds keep their file permissions: bash wsl_build.sh <stage> <work> <account> [--dry-run]
set -euo pipefail

STAGE="$1"
WORK="$2"
ACCOUNT="$3"
DRY_RUN="${4:-}"
TOOLS="$(cd "$(dirname "$0")" && pwd)"
BASE="$HOME/legionus-steam"
APPLE="$BASE/apple"
RCODESIGN="$BASE/bin/rcodesign"
STEAMCMD="$BASE/steamcmd/steamcmd.sh"

rm -rf "$WORK/content"
mkdir -p "$WORK/content" "$WORK/output"

if [ -d "$STAGE/windows" ]; then
  cp -r "$STAGE/windows" "$WORK/content/windows"
fi
if [ -d "$STAGE/linux" ]; then
  cp -r "$STAGE/linux" "$WORK/content/linux"
  chmod 755 "$WORK/content/linux/"*.x86_64
fi
if [ -d "$STAGE/macos" ]; then
  mkdir -p "$WORK/content/macos"
  unzip -q "$STAGE/macos/"*.zip -d "$WORK/content/macos"
  app=$(ls -d "$WORK/content/macos/"*.app)
  chmod 755 "$app/Contents/MacOS/"*
  if [ -f "$APPLE/developer_id.p12" ] && [ -f "$APPLE/api_key.json" ]; then
    "$RCODESIGN" sign --p12-file "$APPLE/developer_id.p12" --p12-password-file "$APPLE/p12_password" \
      --for-notarization --code-signature-flags runtime --entitlements-xml-file "$TOOLS/macos_entitlements.plist" "$app"
    if [ "$DRY_RUN" != "--dry-run" ]; then
      "$RCODESIGN" notary-submit --api-key-file "$APPLE/api_key.json" --staple "$app"
    fi
  elif [ "$DRY_RUN" = "--dry-run" ]; then
    echo "note: no Apple credentials yet, so the Mac app is left unsigned in this dry run"
  else
    echo "publish: the Mac app cannot go to Steam unsigned; make the Apple credentials first (the Release section of CLAUDE.md)" >&2
    exit 1
  fi
fi

if [ "$DRY_RUN" = "--dry-run" ]; then
  echo "dry run: content ready in $WORK/content, nothing uploaded"
  exit 0
fi
"$STEAMCMD" +login "$ACCOUNT" +run_app_build "$STAGE/app_build.vdf" +quit
