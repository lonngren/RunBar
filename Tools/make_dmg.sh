#!/bin/bash
#
# Packages the app into a disk image that looks like a proper installer.
#
# The image holds the app, a symlink to /Applications, and a window
# background with the arrow you drag onto.
#
# Usage:  Tools/make_dmg.sh [app-path] [output-dmg]

set -euo pipefail

APP_PATH="${1:-./build/Build/Products/Release/RunBar.app}"
OUTPUT="${2:-./RunBar.dmg}"
VOLUME_NAME="RunBar"
WINDOW_W="440"
WINDOW_H="620"
ICON_X="164"
ICON_Y="220"

if [ ! -d "$APP_PATH" ]; then
    echo "找不到 App: $APP_PATH"
    exit 1
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

# ---------------------------------------------------------------- background

# The window background: a soft vertical wash with the drag arrow on it.
cat > "$STAGE/background.svg" << SVG
<svg width="$WINDOW_W" height="$WINDOW_H" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#f4f6f9"/>
      <stop offset="100%" stop-color="#dde2ea"/>
    </linearGradient>
  </defs>
  <rect width="100%" height="100%" fill="url(#bg)"/>
  <g transform="translate(296,246)">
    <g fill="none" stroke="#a3a9b3" stroke-width="6" stroke-linecap="round" stroke-linejoin="round">
      <path d="M 92 32 L 34 64 L 92 96"/>
    </g>
  </g>
</svg>
SVG

# Finder wants a PNG for the window picture.
qlmanage -t -s 1600 -o "$STAGE" "$STAGE/background.svg" > /dev/null 2>&1 || true
if [ ! -f "$STAGE/background.svg.png" ]; then
    # Fall back to a plain gradient if Quick Look could not render the SVG.
    sips -s format png --out "$STAGE/background.svg.png" \
        "$STAGE/background.svg" > /dev/null 2>&1 || true
fi
if [ ! -f "$STAGE/background.svg.png" ]; then
    echo "无法生成背景图"
    exit 1
fi

# ---------------------------------------------------------------- build the image

rm -f "$OUTPUT"
# A read-write image first, so the window settings can be written into it.
hdiutil create \
    -srcfolder "$APP_PATH" \
    -volname "$VOLUME_NAME" \
    -fs HFS+ \
    -format UDRW \
    -size 80m \
    "$STAGE/RunBar.dmg" > /dev/null

MOUNT_DIR="$(mktemp -d)"
hdiutil attach "$STAGE/RunBar.dmg" -mountpoint "$MOUNT_DIR" -nobrowse > /dev/null

# The app itself, the symlink, and the background.
rm -rf "$MOUNT_DIR/$VOLUME_NAME.app"
cp -R "$APP_PATH" "$MOUNT_DIR/"
ln -sf /Applications "$MOUNT_DIR/Applications"
mkdir -p "$MOUNT_DIR/.background"
cp "$STAGE/background.svg.png" "$MOUNT_DIR/.background/background.png"

# The window's size, icon placement, and background picture.
cat > "$MOUNT_DIR/.DS_Store" << PLIST
{
  "windowBounds" = { "$ICON_X", "$ICON_Y", "$WINDOW_W", "$WINDOW_H" };
  "backgroundType" = "picture";
  "backgroundPictureAlias" = "background.png";
  "iconLocations" = { { "$ICON_X", "$ICON_Y" } };
  "showIconPreview" = 1;
  "showItemInfo" = 0;
  "showStatusBar" = 0;
  "showTabView" = 0;
  "showToolbar" = 0;
  "showSidebar" = 0;
  "showPathbar" = 0;
  "showPathTips" = 0;
  "preferredViewStyle" = 0;
  "arrangeBy" = "none";
  "sortBy" = "none";
}
PLIST

hdiutil detach "$MOUNT_DIR" > /dev/null
rmdir "$MOUNT_DIR" 2>/dev/null || true

# Compress into the final read-only image.
hdiutil convert "$STAGE/RunBar.dmg" -format UDZO -imagekey zlib-level=9 -o "$OUTPUT" > /dev/null

echo "DMG 已生成: $OUTPUT"
ls -lh "$OUTPUT"
