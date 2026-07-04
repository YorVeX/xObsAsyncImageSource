#!/bin/bash
# Build script for macOS ARM64 (Apple Silicon) - xObsAsyncImageSource OBS Plugin

# Exit on error
set -e

echo "=== Building xObsAsyncImageSource for macOS ARM64 (Apple Silicon) ==="

# Define paths
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$SRC_DIR/publish/osx-arm64"

echo "Source directory: $SRC_DIR"
echo "Output directory: $OUTPUT_DIR"

# Clean previous build
echo "Cleaning previous build..."
rm -rf "$OUTPUT_DIR"

# Build with NativeAOT as shared library
echo "Running dotnet publish..."
dotnet publish "$SRC_DIR" \
  -c Release \
  -o "$OUTPUT_DIR" \
  -r osx-arm64 \
  /p:DefineConstants=MACOS \
  /p:NativeLib=Shared \
  /p:SelfContained=true

echo ""
echo "=== Build complete! ==="
echo "Output file: $OUTPUT_DIR/xObsAsyncImageSource.dylib"
echo ""
echo "To install manually, copy to:"
echo "  ~/Library/Application Support/obs-studio/plugins/xObsAsyncImageSource/bin/xObsAsyncImageSource.so"
echo ""