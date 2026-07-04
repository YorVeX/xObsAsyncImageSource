#!/bin/bash
# Release script for macOS Universal Binary - creates .tar.xz and .pkg
# Requires: build-macos-universal.sh already run successfully

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$SRC_DIR/publish"
PLUGIN_NAME="xObsAsyncImageSource"
VERSION=$(grep -o '<AssemblyVersion>[^<]*' "$SRC_DIR/xObsAsyncImageSource.csproj" | sed 's/<AssemblyVersion>//')

STAGING_ROOT="$OUTPUT_DIR/macos-universal/staging"
BUNDLE_DIR="$STAGING_ROOT/$PLUGIN_NAME.plugin"
RELEASE_DIR="$OUTPUT_DIR/macos-universal/release"
PACKAGE_NAME="${PLUGIN_NAME}-${VERSION}-macos-universal"

echo "=== Creating release packages for $PLUGIN_NAME v$VERSION ==="

# Check that the staging directory exists
if [ ! -d "$STAGING_ROOT" ]; then
  echo "ERROR: Staging directory not found at $STAGING_ROOT"
  echo "Run build-macos-universal.sh first!"
  exit 1
fi

# Check that the plugin bundle exists inside staging
if [ ! -d "$BUNDLE_DIR" ]; then
  echo "ERROR: Plugin bundle not found at $BUNDLE_DIR"
  exit 1
fi

# Create release directory
mkdir -p "$RELEASE_DIR"

# Validate the bundle and staging structure
echo ""
echo "Validating staging directory..."
if [ -f "$BUNDLE_DIR/Contents/Info.plist" ]; then
  echo "  ✓ Info.plist found"
else
  echo "  ✗ Info.plist missing!"
  exit 1
fi
if [ -f "$BUNDLE_DIR/Contents/MacOS/$PLUGIN_NAME" ]; then
  echo "  ✓ Plugin binary found"
  lipo -info "$BUNDLE_DIR/Contents/MacOS/$PLUGIN_NAME" 2>/dev/null || echo "    (lipo info not available)"
else
  echo "  ✗ Plugin binary missing!"
  exit 1
fi
if [ -d "$STAGING_ROOT/$PLUGIN_NAME/data/locale" ] && [ "$(ls -A "$STAGING_ROOT/$PLUGIN_NAME/data/locale/" 2>/dev/null)" ]; then
  echo "  ✓ Locale files found"
else
  echo "  ⚠ Warning: No locale files found in data/locale/"
fi

echo ""
echo "Staging directory contents:"
find "$STAGING_ROOT" -type f | sort

# 1. Create .tar.xz archive (for manual installation)
echo ""
echo "[1/2] Creating .tar.xz archive..."

# Create a temp directory with just the plugin folder name to ensure clean tar structure
TEMP_PKG_DIR="$OUTPUT_DIR/macos-universal/_pkg_temp"
rm -rf "$TEMP_PKG_DIR"
mkdir -p "$TEMP_PKG_DIR"

# Copy the entire staging tree into the temp dir wrapped in a PLUGIN_NAME folder
# so that extracting the tar gives: xObsAsyncImageSource/ (containing xObsAsyncImageSource.plugin + data/)
mkdir -p "$TEMP_PKG_DIR/$PLUGIN_NAME"
cp -R "$STAGING_ROOT/$PLUGIN_NAME.plugin" "$TEMP_PKG_DIR/$PLUGIN_NAME/"
cp -R "$STAGING_ROOT/$PLUGIN_NAME" "$TEMP_PKG_DIR/$PLUGIN_NAME/"

cd "$TEMP_PKG_DIR"
tar -cJf "$RELEASE_DIR/$PACKAGE_NAME.tar.xz" "$PLUGIN_NAME/"
rm -rf "$TEMP_PKG_DIR"
cd "$SRC_DIR"

echo "Created: $RELEASE_DIR/$PACKAGE_NAME.tar.xz"
ls -lh "$RELEASE_DIR/$PACKAGE_NAME.tar.xz"

# Verify tar contents
echo ""
echo "Verifying .tar.xz contents:"
tar -tJf "$RELEASE_DIR/$PACKAGE_NAME.tar.xz" | head -30

# 2. Create .pkg installer (requires pkgbuild, macOS only)
echo ""
echo "[2/2] Creating .pkg installer..."
if command -v pkgbuild &>/dev/null; then
  pkgbuild \
    --root "$STAGING_ROOT" \
    --install-location "$HOME/Library/Application Support/obs-studio/plugins/" \
    --identifier "com.yorvex.xobsasyncimagesource" \
    --version "$VERSION" \
    "$RELEASE_DIR/$PACKAGE_NAME.pkg"
  echo "Created: $RELEASE_DIR/$PACKAGE_NAME.pkg"
  ls -lh "$RELEASE_DIR/$PACKAGE_NAME.pkg"

  # Optional: verify pkg with pkgutil
  if command -v pkgutil &>/dev/null; then
    echo ""
    echo "Verifying .pkg..."
    pkgutil --check-signature "$RELEASE_DIR/$PACKAGE_NAME.pkg" 2>/dev/null || echo "  Note: Package is not signed (Developer ID needed for signing)"
    echo ""
    echo "Package contents:"
    pkgutil --payload-files "$RELEASE_DIR/$PACKAGE_NAME.pkg" | head -30
  fi
else
  echo "WARNING: pkgbuild not found. Skipping .pkg creation."
  echo "To create a .pkg, run this script on macOS with Xcode command line tools installed."
fi

# 3. Create uninstaller .pkg (separate identifier so postinstall can forget the installer receipt cleanly)
echo ""
echo "[3/3] Creating uninstaller .pkg..."
if command -v pkgbuild &>/dev/null; then
  UNINSTALLER_DIR="$OUTPUT_DIR/macos-universal/_uninstaller_temp"
  UNINSTALLER_SCRIPTS_DIR="$UNINSTALLER_DIR/scripts"
  rm -rf "$UNINSTALLER_DIR"
  mkdir -p "$UNINSTALLER_SCRIPTS_DIR"

  INSTALLER_IDENTIFIER="com.yorvex.xobsasyncimagesource"
  UNINSTALLER_IDENTIFIER="${INSTALLER_IDENTIFIER}.uninstaller"

  # Write the postinstall script that removes files then forgets the receipts
  cat > "$UNINSTALLER_SCRIPTS_DIR/postinstall" << UNINSTALLEOF
#!/bin/bash
# Uninstaller postinstall script for xObsAsyncImageSource
# Removes all plugin files and cleans up the pkgutil receipts

PLUGIN_NAME="$PLUGIN_NAME"
INSTALLER_IDENTIFIER="$INSTALLER_IDENTIFIER"
UNINSTALLER_IDENTIFIER="$UNINSTALLER_IDENTIFIER"
OBS_PLUGINS_DIR="\$HOME/Library/Application Support/obs-studio/plugins"

echo "Uninstalling \$PLUGIN_NAME..."

# Remove the .plugin bundle
if [ -d "\$OBS_PLUGINS_DIR/\$PLUGIN_NAME.plugin" ]; then
  rm -rf "\$OBS_PLUGINS_DIR/\$PLUGIN_NAME.plugin"
  echo "  Removed \$OBS_PLUGINS_DIR/\$PLUGIN_NAME.plugin"
fi

# Remove the data directory
if [ -d "\$OBS_PLUGINS_DIR/\$PLUGIN_NAME" ]; then
  rm -rf "\$OBS_PLUGINS_DIR/\$PLUGIN_NAME"
  echo "  Removed \$OBS_PLUGINS_DIR/\$PLUGIN_NAME"
fi

# Forget the installer receipt (this sticks because the framework writes the
# uninstaller receipt, not the installer one)
if command -v pkgutil &>/dev/null; then
  pkgutil --forget "\$INSTALLER_IDENTIFIER" 2>/dev/null && echo "  Cleared installer receipt"
fi

# Schedule our own receipt to be forgotten in the background after the
# installer framework finishes writing it
(sleep 3; pkgutil --forget "\$UNINSTALLER_IDENTIFIER" 2>/dev/null; rm -f /tmp/\$PLUGIN_NAME-uninstaller-\$\$) &
SCHEDULED_PID=\$!
echo "  Scheduled cleanup (PID \$SCHEDULED_PID)"

echo "Uninstall complete."
exit 0
UNINSTALLEOF

  chmod +x "$UNINSTALLER_SCRIPTS_DIR/postinstall"

  UNINSTALLER_PKG_NAME="${PLUGIN_NAME}-${VERSION}-macos-universal-uninstaller"

  pkgbuild \
    --root "$UNINSTALLER_DIR" \
    --scripts "$UNINSTALLER_SCRIPTS_DIR" \
    --identifier "$UNINSTALLER_IDENTIFIER" \
    --version "$VERSION" \
    --install-location "/tmp/$PLUGIN_NAME-uninstaller" \
    "$RELEASE_DIR/$UNINSTALLER_PKG_NAME.pkg"

  rm -rf "$UNINSTALLER_DIR"
  echo "Created: $RELEASE_DIR/$UNINSTALLER_PKG_NAME.pkg"
  ls -lh "$RELEASE_DIR/$UNINSTALLER_PKG_NAME.pkg"
else
  echo "WARNING: pkgbuild not found. Skipping uninstaller .pkg creation."
fi

echo ""
echo "=== Release complete! ==="
echo ""
echo "Files in $RELEASE_DIR:"
ls -lh "$RELEASE_DIR/"
echo ""
echo "The .tar.xz and installer .pkg contain:"
echo "  $PLUGIN_NAME/"
echo "  ├── $PLUGIN_NAME.plugin/        (OBS plugin bundle)"
echo "  └── data/"
echo "      └── locale/                 (translation files)"
echo ""
echo "The uninstaller .pkg removes all plugin files."
echo ""
echo "Installation (manual):"
echo "  tar -xJf $PACKAGE_NAME.tar.xz -C ~/'Library/Application Support/obs-studio/plugins/'"
echo ""
echo "Uninstallation:"
echo "  open ${PLUGIN_NAME}-${VERSION}-macos-universal-uninstaller.pkg"
echo ""
echo "For signing (requires Apple Developer account):"
echo "  codesign --force --deep --sign 'Developer ID Application: ...' $BUNDLE_DIR"
echo "  pkgbuild --root $STAGING_ROOT --install-location ... --sign 'Developer ID Installer: ...' $PACKAGE_NAME.pkg"