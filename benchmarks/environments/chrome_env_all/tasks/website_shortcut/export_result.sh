#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Website Shortcut Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window to ensure everything is synced
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Create export directory
EXPORT_DIR="/tmp/shortcut_verification"
mkdir -p "$EXPORT_DIR"

# Capture active tab URL via CDP for verification context
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > "$EXPORT_DIR/final_url.txt"
fi

# List desktop directory contents
DESKTOP_DIR="/home/ga/Desktop"
echo "Checking desktop directory for .desktop files..."

if [ -d "$DESKTOP_DIR" ]; then
    echo "Desktop directory exists"
    ls -la "$DESKTOP_DIR" || true
    
    # Count .desktop files
    DESKTOP_COUNT=$(find "$DESKTOP_DIR" -maxdepth 1 -name "*.desktop" -type f 2>/dev/null | wc -l)
    echo "Found $DESKTOP_COUNT .desktop file(s)"
    
    # Copy all .desktop files to export directory
    if [ "$DESKTOP_COUNT" -gt 0 ]; then
        echo "Copying .desktop files to export directory..."
        cp -v "$DESKTOP_DIR"/*.desktop "$EXPORT_DIR/" 2>/dev/null || true
        
        # List what was copied
        echo "Exported files:"
        ls -lh "$EXPORT_DIR"/*.desktop 2>/dev/null || echo "No .desktop files copied"
        
        # Save file list
        find "$DESKTOP_DIR" -maxdepth 1 -name "*.desktop" -type f -exec basename {} \; > "$EXPORT_DIR/desktop_files_list.txt" 2>/dev/null
    else
        echo "⚠ No .desktop files found on desktop"
        echo "none" > "$EXPORT_DIR/desktop_files_list.txt"
    fi
else
    echo "⚠ Desktop directory does not exist: $DESKTOP_DIR"
    echo "error" > "$EXPORT_DIR/desktop_files_list.txt"
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root $EXPORT_DIR/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved"
fi

# Copy export directory contents to standard temp location for verifier
cp -r "$EXPORT_DIR"/* /tmp/ 2>/dev/null || true

# Also try to copy directly from desktop for fallback verification
mkdir -p /tmp/desktop_backup
cp "$DESKTOP_DIR"/*.desktop /tmp/desktop_backup/ 2>/dev/null || true

echo "✅ Export complete"
echo "Verification files available in: $EXPORT_DIR"