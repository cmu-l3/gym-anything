#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Selective Privacy Clear Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq sqlite3 || true

# Focus Chrome window one last time
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture active tab URL for context
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
fi

# Take a final screenshot
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# Gracefully close Chrome to ensure all data is flushed to disk
echo "Closing Chrome to save changes..."
pkill -f "google-chrome" || true
sleep 3

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Create verification directory
VERIFY_DIR="/tmp/privacy_clear_verification"
mkdir -p "$VERIFY_DIR"

# Export Chrome profile files for verification
echo "Exporting Chrome data files for verification..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
ALT_PROFILE="/home/ga/.config/google-chrome/Default"

# Try to copy History database
if [ -f "$CHROME_PROFILE/History" ]; then
    cp "$CHROME_PROFILE/History" "$VERIFY_DIR/History"
    echo "✓ History database copied"
    # Get history count for logging
    HISTORY_COUNT=$(sqlite3 "$VERIFY_DIR/History" "SELECT COUNT(*) FROM urls;" 2>/dev/null || echo "unknown")
    echo "  History has $HISTORY_COUNT URL entries"
elif [ -f "$ALT_PROFILE/History" ]; then
    cp "$ALT_PROFILE/History" "$VERIFY_DIR/History"
    echo "✓ History database copied from alternative location"
else
    echo "⚠ Warning: History database not found"
    touch "$VERIFY_DIR/History"
fi

# Try to copy Cookies database
if [ -f "$CHROME_PROFILE/Cookies" ]; then
    cp "$CHROME_PROFILE/Cookies" "$VERIFY_DIR/Cookies"
    echo "✓ Cookies database copied"
    # Get cookie count for logging
    COOKIE_COUNT=$(sqlite3 "$VERIFY_DIR/Cookies" "SELECT COUNT(*) FROM cookies;" 2>/dev/null || echo "unknown")
    echo "  Cookies database has $COOKIE_COUNT entries"
elif [ -f "$ALT_PROFILE/Cookies" ]; then
    cp "$ALT_PROFILE/Cookies" "$VERIFY_DIR/Cookies"
    echo "✓ Cookies database copied from alternative location"
else
    echo "⚠ Warning: Cookies database not found"
    touch "$VERIFY_DIR/Cookies"
fi

# Try to copy Bookmarks file
if [ -f "$CHROME_PROFILE/Bookmarks" ]; then
    cp "$CHROME_PROFILE/Bookmarks" "$VERIFY_DIR/Bookmarks"
    echo "✓ Bookmarks file copied"
    # Verify bookmarks exist
    BOOKMARK_COUNT=$(jq '[.roots.bookmark_bar.children | length] + [.roots.other.children | length] | add' "$VERIFY_DIR/Bookmarks" 2>/dev/null || echo "unknown")
    echo "  Bookmarks file has $BOOKMARK_COUNT top-level entries"
elif [ -f "$ALT_PROFILE/Bookmarks" ]; then
    cp "$ALT_PROFILE/Bookmarks" "$VERIFY_DIR/Bookmarks"
    echo "✓ Bookmarks file copied from alternative location"
else
    echo "⚠ Warning: Bookmarks file not found"
    echo '{"roots":{"bookmark_bar":{"children":[]}}}' > "$VERIFY_DIR/Bookmarks"
fi

# Try to copy Preferences file for additional context
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" "$VERIFY_DIR/Preferences"
    echo "✓ Preferences file copied"
elif [ -f "$ALT_PROFILE/Preferences" ]; then
    cp "$ALT_PROFILE/Preferences" "$VERIFY_DIR/Preferences"
    echo "✓ Preferences file copied from alternative location"
fi

# Check Cache directory size
CACHE_DIR="$CHROME_PROFILE/Cache"
ALT_CACHE_DIR="$ALT_PROFILE/Cache"
if [ -d "$CACHE_DIR" ]; then
    CACHE_SIZE=$(du -sb "$CACHE_DIR" 2>/dev/null | cut -f1 || echo "0")
    CACHE_FILES=$(find "$CACHE_DIR" -type f 2>/dev/null | wc -l || echo "0")
    echo "✓ Cache directory size: $CACHE_SIZE bytes ($CACHE_FILES files)"
    echo "$CACHE_SIZE" > "$VERIFY_DIR/cache_size.txt"
    echo "$CACHE_FILES" > "$VERIFY_DIR/cache_files.txt"
elif [ -d "$ALT_CACHE_DIR" ]; then
    CACHE_SIZE=$(du -sb "$ALT_CACHE_DIR" 2>/dev/null | cut -f1 || echo "0")
    CACHE_FILES=$(find "$ALT_CACHE_DIR" -type f 2>/dev/null | wc -l || echo "0")
    echo "✓ Cache directory size: $CACHE_SIZE bytes ($CACHE_FILES files)"
    echo "$CACHE_SIZE" > "$VERIFY_DIR/cache_size.txt"
    echo "$CACHE_FILES" > "$VERIFY_DIR/cache_files.txt"
else
    echo "⚠ Cache directory not found or already cleared"
    echo "0" > "$VERIFY_DIR/cache_size.txt"
    echo "0" > "$VERIFY_DIR/cache_files.txt"
fi

echo "✅ Export complete"
echo "Verification files ready in: $VERIFY_DIR"