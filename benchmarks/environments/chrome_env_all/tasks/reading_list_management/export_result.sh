#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Reading List Management Task Export: reading_list_management@1 ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq sqlite3 || true

# Focus Chrome window one last time
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture active tab URL via CDP for additional context
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# Gracefully close Chrome to ensure Reading List is persisted to disk
echo "Closing Chrome to save Reading List data..."
pkill -f "google-chrome" || true
sleep 2

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Export Reading List data to temporary location for verification
echo "Exporting Chrome Reading List data..."

# Create verification directory
VERIFY_DIR="/tmp/reading_list_verification"
mkdir -p "$VERIFY_DIR"

# Try to locate and copy Reading List database (newer Chrome versions)
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
ALT_PROFILE="/home/ga/.config/google-chrome/Default"

# Check for Reading List SQLite database
if [ -f "$CHROME_PROFILE/Reading List" ]; then
    echo "✓ Found Reading List database at: $CHROME_PROFILE/Reading List"
    cp "$CHROME_PROFILE/Reading List" "$VERIFY_DIR/reading_list.db"
    
    # Try to dump database contents for debugging
    if command -v sqlite3 &> /dev/null; then
        sqlite3 "$VERIFY_DIR/reading_list.db" ".tables" > "$VERIFY_DIR/db_tables.txt" 2>/dev/null || true
        sqlite3 "$VERIFY_DIR/reading_list.db" "SELECT * FROM reading_list;" > "$VERIFY_DIR/db_dump.txt" 2>/dev/null || true
        echo "✓ Database dumped for debugging"
    fi
elif [ -f "$ALT_PROFILE/Reading List" ]; then
    echo "✓ Found Reading List database at: $ALT_PROFILE/Reading List"
    cp "$ALT_PROFILE/Reading List" "$VERIFY_DIR/reading_list.db"
else
    echo "⚠ Reading List database not found (may be stored in Preferences or Local State)"
fi

# Also copy Preferences and Local State (fallback storage locations)
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" "$VERIFY_DIR/preferences.json"
    echo "✓ Preferences copied"
elif [ -f "$ALT_PROFILE/Preferences" ]; then
    cp "$ALT_PROFILE/Preferences" "$VERIFY_DIR/preferences.json"
    echo "✓ Preferences copied from alternative location"
fi

if [ -f "$CHROME_PROFILE/Local State" ]; then
    cp "$CHROME_PROFILE/Local State" "$VERIFY_DIR/local_state.json"
    echo "✓ Local State copied"
elif [ -f "/home/ga/.config/google-chrome-cdp/Local State" ]; then
    cp "/home/ga/.config/google-chrome-cdp/Local State" "$VERIFY_DIR/local_state.json"
    echo "✓ Local State copied from alternative location"
fi

# List all files in verification directory
echo "Files prepared for verification:"
ls -lah "$VERIFY_DIR/" || true

# Copy verification directory contents to standard temp location
cp -r "$VERIFY_DIR"/* /tmp/ 2>/dev/null || true

echo "✅ Export complete"
echo "Reading List data exported to: $VERIFY_DIR"