#!/bin/bash
# Test deployment script for macOS - copies built plugin to OBS plugins folder

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== Deploying xObsAsyncImageSource to OBS plugins folder for testing ==="

# Detect architecture
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
    BUILD_DIR="$SRC_DIR/publish/osx-arm64"
    echo "Detected Apple Silicon (ARM64)"
elif [ "$ARCH" = "x86_64" ]; then
    BUILD_DIR="$SRC_DIR/publish/osx-x64"
    echo "Detected Intel (x64)"
else
    echo "Unknown architecture: $ARCH"
    exit 1
fi

if [ ! -f "$BUILD_DIR/xObsAsyncImageSource.dylib" ]; then
    echo "Error: Built plugin not found at $BUILD_DIR/xObsAsyncImageSource.dylib"
    echo "Please run the build task first!"
    exit 1
fi

# OBS plugins directory
OBS_PLUGINS_DIR="$HOME/Library/Application Support/obs-studio/plugins"

echo "Removing any leftover xObsAsyncImageSource.plugin directory from previous runs..."
rm -rf "$OBS_PLUGINS_DIR/xObsAsyncImageSource.plugin"

echo "Creating plugin data directory structure..."
mkdir -p "$OBS_PLUGINS_DIR/xObsAsyncImageSource/data/locale"

echo "Copying plugin binary as xObsAsyncImageSource.plugin..."
cp "$BUILD_DIR/xObsAsyncImageSource.dylib" "$OBS_PLUGINS_DIR/xObsAsyncImageSource.plugin"

# Copy locale files
echo "Copying locale files..."
cp "$SRC_DIR/locale/"*.ini "$OBS_PLUGINS_DIR/xObsAsyncImageSource/data/locale/"

echo ""
echo "=== Deployment complete! ==="
echo "Plugin installed at: $OBS_PLUGINS_DIR"
echo ""
echo "Restart OBS Studio to load the plugin."