#!/bin/bash
set -euo pipefail

echo "=== Exporting Cemetery Workstation Task Result ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Gracefully close Chrome to flush all data to disk
echo "Closing Chrome to flush data..."
pkill -f "chrome" 2>/dev/null || true
sleep 3
pkill -9 -f "chrome" 2>/dev/null || true
sleep 1

# 3. Export important Chrome files to /tmp/ for verifier access
EXPORT_DIR="/tmp/cemetery_export"
rm -rf "$EXPORT_DIR"
mkdir -p "$EXPORT_DIR"

PROFILE_DIR="/home/ga/.config/google-chrome/Default"

if [ -f "$PROFILE_DIR/Bookmarks" ]; then
    cp "$PROFILE_DIR/Bookmarks" "$EXPORT_DIR/Bookmarks"
fi

if [ -f "$PROFILE_DIR/Preferences" ]; then
    cp "$PROFILE_DIR/Preferences" "$EXPORT_DIR/Preferences"
fi

if [ -f "$PROFILE_DIR/History" ]; then
    cp "$PROFILE_DIR/History" "$EXPORT_DIR/History"
fi

if [ -f "$PROFILE_DIR/Web Data" ]; then
    cp "$PROFILE_DIR/Web Data" "$EXPORT_DIR/Web Data"
fi

chmod -R 777 "$EXPORT_DIR"

echo "=== Export Complete ==="