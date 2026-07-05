#!/bin/bash
# Build macOS Universal Binary (.plugin bundle) for xObsAsyncImageSource
# Creates a single .plugin that contains both arm64 and x86_64 architectures

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$SRC_DIR/publish"
PLUGIN_NAME="xObsAsyncImageSource"
VERSION=$(grep -o '<AssemblyVersion>[^<]*' "$SRC_DIR/xObsAsyncImageSource.csproj" | sed 's/<AssemblyVersion>//')

echo "=== Building $PLUGIN_NAME v$VERSION for macOS Universal ==="
echo "Setting MACOS_DEPLOYMENT_TARGET=12.0"
export MACOS_DEPLOYMENT_TARGET=12.0

# 1. Build for arm64
echo ""
echo "[1/5] Building for arm64..."
dotnet publish "$SRC_DIR" \
  -c Release \
  -o "$OUTPUT_DIR/osx-arm64" \
  -r osx-arm64 \
  /p:DefineConstants=MACOS \
  /p:NativeLib=Shared \
  /p:SelfContained=true

# 2. Build for x64
echo ""
echo "[2/5] Building for x64..."
dotnet publish "$SRC_DIR" \
  -c Release \
  -o "$OUTPUT_DIR/osx-x64" \
  -r osx-x64 \
  /p:DefineConstants=MACOS \
  /p:NativeLib=Shared \
  /p:SelfContained=true

# 3. Create universal binary with lipo
echo ""
echo "[3/5] Creating universal binary..."
UNIVERSAL_DIR="$OUTPUT_DIR/macos-universal"
rm -rf "$UNIVERSAL_DIR"
mkdir -p "$UNIVERSAL_DIR"

lipo -create \
  "$OUTPUT_DIR/osx-arm64/$PLUGIN_NAME.dylib" \
  "$OUTPUT_DIR/osx-x64/$PLUGIN_NAME.dylib" \
  -output "$UNIVERSAL_DIR/$PLUGIN_NAME.dylib"

echo "Universal binary created: $UNIVERSAL_DIR/$PLUGIN_NAME.dylib"
lipo -info "$UNIVERSAL_DIR/$PLUGIN_NAME.dylib"

# 4. Create staging directory (browsable plain files, not a .plugin bundle)
echo ""
echo "[4/5] Creating staging directory..."

RELEASE_DIR="$SRC_DIR/release/macos-universal"
STAGING_ROOT="$RELEASE_DIR/staging"
BUNDLE_BIN_DIR="$STAGING_ROOT/bin"
BUNDLE_DATA_DIR="$STAGING_ROOT/data"

rm -rf "$STAGING_ROOT"
mkdir -p "$BUNDLE_BIN_DIR"
mkdir -p "$BUNDLE_DATA_DIR/locale"

# Copy the universal binary (keeps .dylib name in staging, release script strips it for the plugin bundle)
cp "$UNIVERSAL_DIR/$PLUGIN_NAME.dylib" "$BUNDLE_BIN_DIR/$PLUGIN_NAME"

# Copy locale files
if [ -d "$SRC_DIR/locale" ]; then
  cp "$SRC_DIR/locale/"*.ini "$BUNDLE_DATA_DIR/locale/"
  echo "Copied locale files ($(ls "$SRC_DIR/locale/"*.ini 2>/dev/null | wc -l | tr -d ' ') files: $(ls "$SRC_DIR/locale/"*.ini 2>/dev/null | xargs -n1 basename | tr '\n' ' '))"
fi

# Create Info.plist in staging (metadata for the plugin bundle)
cat > "$STAGING_ROOT/Info.plist" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>English</string>
    <key>CFBundleExecutable</key>
    <string>$PLUGIN_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.yorvex.xobsasyncimagesource</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$PLUGIN_NAME</string>
    <key>CFBundlePackageType</key>
    <string>BNDL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>NSHumanReadableCopyright</key>
    <string>© 2023-2026 YorVeX, https://github.com/YorVeX. Licensed under MIT.</string>
    <key>CFBundleGetInfoString</key>
    <string>$VERSION, Copyright © 2023-2026 YorVeX</string>
    <key>MinimumOSVersion</key>
    <string>12.0</string>
</dict>
</plist>
PLISTEOF
echo "Info.plist created"

# Verify staging structure
echo ""
echo "Staging directory structure:"
find "$STAGING_ROOT" -type f | sort

echo ""
echo "=== Build complete! ==="
echo "Staging directory: $STAGING_ROOT"
echo "Universal binary: $UNIVERSAL_DIR/$PLUGIN_NAME.dylib"