#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Site Security Verification Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq imagemagick || true

# Focus Chrome window
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Create verification directory
VERIFY_DIR="/tmp/security_check_verification"
mkdir -p "$VERIFY_DIR"

# Record end time for duration calculation
date +%s > "$VERIFY_DIR/task_end_time.txt"

# Capture all tabs via CDP
echo "Capturing all tabs information via CDP..."
if curl -s http://localhost:9222/json > "$VERIFY_DIR/chrome_all_tabs.json" 2>/dev/null; then
    echo "✓ Successfully captured CDP tab information"
    
    # Filter to only page-type tabs
    jq '[.[] | select(.type == "page")]' "$VERIFY_DIR/chrome_all_tabs.json" > "$VERIFY_DIR/chrome_page_tabs.json"
    
    TAB_COUNT=$(jq 'length' "$VERIFY_DIR/chrome_page_tabs.json")
    echo "✓ Found $TAB_COUNT page tab(s)"
    
    # Extract active tab information
    ACTIVE_TAB=$(jq '[.[] | select(.type == "page")][0]' "$VERIFY_DIR/chrome_all_tabs.json")
    echo "$ACTIVE_TAB" > "$VERIFY_DIR/active_tab.json"
    
    ACTIVE_URL=$(echo "$ACTIVE_TAB" | jq -r '.url // ""')
    ACTIVE_TITLE=$(echo "$ACTIVE_TAB" | jq -r '.title // ""')
    
    echo "Active tab URL: $ACTIVE_URL"
    echo "Active tab title: $ACTIVE_TITLE"
    
    # Save URL and title separately for easy access
    echo "$ACTIVE_URL" > "$VERIFY_DIR/active_url.txt"
    echo "$ACTIVE_TITLE" > "$VERIFY_DIR/active_title.txt"
    
    # Extract all tab URLs for history
    jq -r '.[] | .url' "$VERIFY_DIR/chrome_page_tabs.json" > "$VERIFY_DIR/all_urls.txt"
    
else
    echo "⚠ Warning: Failed to capture CDP information"
    echo "" > "$VERIFY_DIR/active_url.txt"
    echo "" > "$VERIFY_DIR/active_title.txt"
    echo "[]" > "$VERIFY_DIR/chrome_page_tabs.json"
fi

# Take a final screenshot for debugging
echo "Capturing final screenshot..."
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root $VERIFY_DIR/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to $VERIFY_DIR/final_screenshot.png"
fi

# Try to capture a zoomed-in screenshot of address bar area (for padlock icon)
echo "Capturing address bar region..."
if command -v import &> /dev/null; then
    # Crop top 150 pixels where address bar is typically located
    su - ga -c "DISPLAY=:1 import -window root $VERIFY_DIR/full_screenshot.png" 2>/dev/null || true
    if [ -f "$VERIFY_DIR/full_screenshot.png" ]; then
        convert "$VERIFY_DIR/full_screenshot.png" -crop 800x150+0+0 "$VERIFY_DIR/address_bar.png" 2>/dev/null || true
        echo "Address bar screenshot saved"
    fi
fi

# Copy Chrome history for URL verification
echo "Exporting Chrome history..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/History" ]; then
    # History is SQLite DB, might be locked if Chrome is running
    # Try to copy it
    cp "$CHROME_PROFILE/History" "$VERIFY_DIR/History.db" 2>/dev/null || true
    if [ -f "$VERIFY_DIR/History.db" ]; then
        echo "✓ History database copied"
    else
        echo "⚠ Could not copy History database (might be locked)"
    fi
else
    echo "⚠ History file not found at $CHROME_PROFILE/History"
fi

# Alternative: Try without closing Chrome first (CDP provides enough info)
# If needed, we can close Chrome to unlock History file:
# pkill -f "google-chrome" || true
# sleep 2
# Then copy History

# Copy all verification files to standard /tmp location
cp -r "$VERIFY_DIR"/* /tmp/ 2>/dev/null || true

echo "✅ Export complete"
echo "Verification files available in: $VERIFY_DIR"
ls -lh "$VERIFY_DIR/" || true