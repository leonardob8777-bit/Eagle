#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"
DERIVED_DATA="$BUILD_DIR/DerivedData"
PRODUCT_NAME="Eagle"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/private/tmp}/eagle-ipa.XXXXXX")"
VERIFY_MATRIX_SCRIPT="$PROJECT_ROOT/scripts/verify_prepare_matrices.sh"
VERIFY_POINTER_GUARDS_SCRIPT="$PROJECT_ROOT/scripts/verify_kernel_pointer_guards.sh"

cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

mkdir -p "$BUILD_DIR"
if [ "${EAGLE_REUSE_DERIVED_DATA:-0}" != "1" ]; then
  rm -rf "$DERIVED_DATA"
fi
rm -f "$BUILD_DIR/xcodebuild.log" "$BUILD_DIR/$PRODUCT_NAME.ipa"

if [ ! -x "$VERIFY_MATRIX_SCRIPT" ]; then
  echo "ERROR: compatibility verifier is missing or not executable: $VERIFY_MATRIX_SCRIPT" >&2
  exit 1
fi

"$VERIFY_MATRIX_SCRIPT"

if [ ! -x "$VERIFY_POINTER_GUARDS_SCRIPT" ]; then
  echo "ERROR: kernel pointer verifier is missing or not executable: $VERIFY_POINTER_GUARDS_SCRIPT" >&2
  exit 1
fi

"$VERIFY_POINTER_GUARDS_SCRIPT"

echo "Building Eagle release..."
xcodebuild \
  -project "$PROJECT_ROOT/lara.xcodeproj" \
  -scheme lara \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build 2>&1 | tee "$BUILD_DIR/xcodebuild.log"

BUILT_APP="$DERIVED_DATA/Build/Products/Release-iphoneos/$PRODUCT_NAME.app"
if [ ! -d "$BUILT_APP" ]; then
  echo "ERROR: expected app was not produced at $BUILT_APP" >&2
  exit 1
fi

# An incremental Release build can extract the current intents while skipping
# their SSU training phase. Generate from this build's metadata, never from an
# older IPA, so Scenes/Moments retain their English and Spanish shortcuts.
if [ -f "$BUILT_APP/Metadata.appintents/extract.actionsdata" ]; then
  INTENTS_TEMP="$STAGING_DIR/app-intents"
  mkdir -p "$INTENTS_TEMP"
  APP_BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$BUILT_APP/Info.plist")
  xcrun appintentsnltrainingprocessor \
    --extracted-metadata-path "$BUILT_APP/Metadata.appintents" \
    --infoplist-path "$BUILT_APP/Info.plist" \
    --bundle-id "$APP_BUNDLE_ID" \
    --product-path "$BUILT_APP" \
    --temp-dir-path "$INTENTS_TEMP" \
    --archive-ssu-assets
fi

PAYLOAD_DIR="$STAGING_DIR/Payload"
PACKAGED_APP="$PAYLOAD_DIR/$PRODUCT_NAME.app"
mkdir -p "$PAYLOAD_DIR"
cp -R -X "$BUILT_APP" "$PACKAGED_APP"

# File-provider workspaces can attach Finder metadata to copied bundles. Those
# attributes are not part of Eagle and can make downstream signing fail.
xattr -cr "$PACKAGED_APP" 2>/dev/null || true

codesign --remove-signature "$PACKAGED_APP" 2>/dev/null || true

# CODE_SIGNING_ALLOWED=NO deliberately leaves embedded Mach-O files unsigned.
# A direct device install then fails in dyld before Eagle can launch. Sign and
# verify every embedded executable before signing the main binary and zipping
# the payload. Sideloading tools may replace these ad-hoc signatures later.
EMBEDDED_BINARIES=(
  "$PACKAGED_APP/Frameworks/libgrabkernel2.dylib"
  "$PACKAGED_APP/Frameworks/libxpf.dylib"
)

for binary in "${EMBEDDED_BINARIES[@]}"; do
  if [ ! -f "$binary" ]; then
    echo "ERROR: expected embedded binary was not produced: $binary" >&2
    exit 1
  fi
  codesign --remove-signature "$binary" 2>/dev/null || true
  codesign --force --sign - --timestamp=none "$binary"
  codesign --verify --strict --verbose=2 "$binary"
done

codesign \
  --force \
  --sign - \
  --entitlements "$PROJECT_ROOT/Config/lara.entitlements" \
  --generate-entitlement-der \
  --timestamp=none \
  "$PACKAGED_APP"
codesign --verify --deep --strict --verbose=2 "$PACKAGED_APP"

(cd "$STAGING_DIR" && /usr/bin/zip -qryX "$BUILD_DIR/$PRODUCT_NAME.ipa" Payload)

echo "Eagle IPA: $BUILD_DIR/$PRODUCT_NAME.ipa"
