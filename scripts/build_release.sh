#!/usr/bin/env bash
# Builds a Release archive and exports build/Switches.app.
#
#   scripts/build_release.sh              # signed with your Apple Development identity (or ad-hoc)
#   scripts/build_release.sh --notarize   # Developer ID export + notarization (needs NOTARY_PROFILE)
#
# Env: DEVELOPMENT_TEAM overrides the team ID detected from the keychain.
set -euo pipefail
cd "$(dirname "$0")/.."

NOTARIZE=0
[[ "${1:-}" == "--notarize" ]] && NOTARIZE=1

BUILD_DIR=build
ARCHIVE="$BUILD_DIR/Switches.xcarchive"
APP="$BUILD_DIR/Switches.app"

if [[ ! -f Switches/Resources/Themes/Cardboard/theme.json ]]; then
  echo "No converted themes found; running convert-sounds first" >&2
  swift scripts/convert_sounds.swift
fi

xcodegen generate --quiet

team="${DEVELOPMENT_TEAM:-}"
if [[ -z "$team" ]]; then
  team="$(security find-certificate -c "Apple Development" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null \
    | sed -n 's/.*OU *= *\([A-Z0-9]\{10\}\).*/\1/p' | head -1 || true)"
fi

signing_args=()
if [[ -n "$team" ]]; then
  echo "Signing with team $team" >&2
  signing_args=(DEVELOPMENT_TEAM="$team" CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates)
else
  echo "No Apple Development identity found; signing ad-hoc (Input Monitoring must be re-granted after each install)" >&2
  signing_args=(CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=)
fi

rm -rf "$ARCHIVE" "$APP"
mkdir -p "$BUILD_DIR"
xcodebuild \
  -project Switches.xcodeproj \
  -scheme Switches \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  "${signing_args[@]}" \
  -quiet \
  archive

if [[ "$NOTARIZE" == 1 ]]; then
  : "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool keychain profile}"
  cat >"$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>${team}</string>
</dict>
</plist>
PLIST
  xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$BUILD_DIR" \
    -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" -allowProvisioningUpdates -quiet
  ditto -c -k --keepParent "$APP" "$BUILD_DIR/Switches-notarize.zip"
  xcrun notarytool submit "$BUILD_DIR/Switches-notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
else
  ditto "$ARCHIVE/Products/Applications/Switches.app" "$APP"
fi

codesign --verify --deep --strict "$APP"
echo "Built $APP"
