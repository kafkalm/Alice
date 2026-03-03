#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Alice.xcodeproj"
SCHEME="${SCHEME:-AliceDesktop}"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$HOME/Library/Developer/Xcode/DerivedData/AliceDev-Stable}"
DEV_BUNDLE_ID="${DEV_BUNDLE_ID:-com.kafkalm.alice.dev}"
DEV_TEAM_ID="${DEV_TEAM_ID:-}"
DEV_CODE_SIGN_IDENTITY="${DEV_CODE_SIGN_IDENTITY:-}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
INSTALL_APP_NAME="${INSTALL_APP_NAME:-AliceDev}"
INSTALL_APP_PATH="$INSTALL_DIR/$INSTALL_APP_NAME.app"
BUILT_APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/AliceMac.app"

IDENTITY_LINE="$(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development:" | head -n1 || true)"

if [[ -z "$DEV_CODE_SIGN_IDENTITY" ]] && [[ -n "$IDENTITY_LINE" ]]; then
  DEV_CODE_SIGN_IDENTITY="$(awk '{print $2}' <<<"$IDENTITY_LINE")"
fi

if [[ -z "$DEV_TEAM_ID" ]] && [[ -n "$IDENTITY_LINE" ]]; then
  DEV_TEAM_ID="$(sed -n 's/.*(\([A-Z0-9]\{10\}\)).*/\1/p' <<<"$IDENTITY_LINE")"
fi

if [[ -z "$DEV_TEAM_ID" ]]; then
  echo "[dev-run] no Apple Development identity found."
  echo "[dev-run] open Xcode and sign in with your Apple ID first."
  exit 1
fi

if [[ -z "$DEV_CODE_SIGN_IDENTITY" ]]; then
  echo "[dev-run] cannot determine Apple Development certificate fingerprint."
  exit 1
fi

echo "[dev-run] project: $PROJECT_PATH"
echo "[dev-run] scheme: $SCHEME"
echo "[dev-run] configuration: $CONFIGURATION"
echo "[dev-run] bundle id: $DEV_BUNDLE_ID"
echo "[dev-run] development team: $DEV_TEAM_ID"
echo "[dev-run] code sign identity: $DEV_CODE_SIGN_IDENTITY"
echo "[dev-run] derived data: $DERIVED_DATA_PATH"
echo "[dev-run] install app: $INSTALL_APP_PATH"

if pgrep -x "AliceMac" >/dev/null 2>&1; then
  echo "[dev-run] stopping running AliceMac process..."
  killall AliceMac || true
  sleep 1
fi

echo "[dev-run] building..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$DEV_CODE_SIGN_IDENTITY" \
  DEVELOPMENT_TEAM="$DEV_TEAM_ID" \
  PRODUCT_BUNDLE_IDENTIFIER="$DEV_BUNDLE_ID" \
  build >/tmp/alice-dev-run-xcodebuild.log

if [[ ! -d "$BUILT_APP_PATH" ]]; then
  echo "[dev-run] build output not found: $BUILT_APP_PATH"
  echo "[dev-run] last xcodebuild log:"
  tail -n 120 /tmp/alice-dev-run-xcodebuild.log || true
  exit 1
fi

mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_APP_PATH"
cp -R "$BUILT_APP_PATH" "$INSTALL_APP_PATH"

echo "[dev-run] launching app..."
open "$INSTALL_APP_PATH"

echo "[dev-run] signing summary:"
codesign -dv --verbose=4 "$INSTALL_APP_PATH" 2>&1 | grep -E "Identifier=|TeamIdentifier=|Authority="

echo "[dev-run] done."
echo "[dev-run] first run may ask for permissions."
echo "[dev-run] afterwards, keep using this script to reduce repeated permission prompts."
