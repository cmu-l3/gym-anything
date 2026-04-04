#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Reading List Task Export: reading_list_add@1 ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture active tab URL via CDP for verification
echo "Capturing active tab information via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs_final.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs_final.json)
    ACTIVE_TITLE=$(jq -r '[.[] | select(.type == "page")][0].title // ""' /tmp/chrome_tabs_final.json)
    echo "Active URL: $ACTIVE_URL"
    echo "Active Title: $ACTIVE_TITLE"
    echo "$ACTIVE_URL" > /tmp/final_active_url.txt
    echo "$ACTIVE_TITLE" > /tmp/final_active_title.txt
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/reading_list_final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/reading_list_final_screenshot.png"
fi

# Record task end time
echo "$(date +%s)" > /tmp/task_end_time.txt

# Gracefully close Chrome to ensure Reading List data is persisted to disk
echo "Closing Chrome to persist Reading List data..."
pkill -f "google-chrome" || true
sleep 3

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 2
fi

# Export Chrome data files that may contain Reading List information
echo "Exporting Chrome Reading List data..."

# Create temporary directory for exports
EXPORT_DIR="/tmp/reading_list_export"
mkdir -p "$EXPORT_DIR"

# Try primary Chrome profile location
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -d "$CHROME_PROFILE" ]; then
    echo "Exporting from primary profile: $CHROME_PROFILE"
    
    # Copy Preferences (most likely location for Reading List in modern Chrome)
    if [ -f "$CHROME_PROFILE/Preferences" ]; then
        cp "$CHROME_PROFILE/Preferences" "$EXPORT_DIR/Preferences.json"
        echo "✓ Preferences exported"
    fi
    
    # Copy Local State (alternative location)
    if [ -f "$CHROME_PROFILE/../Local State" ]; then
        cp "$CHROME_PROFILE/../Local State" "$EXPORT_DIR/LocalState.json"
        echo "✓ Local State exported"
    fi
    
    # Copy ReadingList file if it exists (older Chrome versions)
    if [ -f "$CHROME_PROFILE/ReadingList" ]; then
        cp "$CHROME_PROFILE/ReadingList" "$EXPORT_DIR/ReadingList"
        echo "✓ ReadingList file exported"
    fi
    
    # Try ReadingListDB (SQLite database in some versions)
    if [ -f "$CHROME_PROFILE/ReadingListDB" ]; then
        cp "$CHROME_PROFILE/ReadingListDB" "$EXPORT_DIR/ReadingListDB"
        echo "✓ ReadingListDB exported"
    fi
fi

# Try alternative Chrome profile location
ALT_PROFILE="/home/ga/.config/google-chrome/Default"
if [ -d "$ALT_PROFILE" ] && [ "$ALT_PROFILE" != "$CHROME_PROFILE" ]; then
    echo "Checking alternative profile: $ALT_PROFILE"
    
    if [ -f "$ALT_PROFILE/Preferences" ] && [ ! -f "$EXPORT_DIR/Preferences.json" ]; then
        cp "$ALT_PROFILE/Preferences" "$EXPORT_DIR/Preferences.json"
        echo "✓ Preferences exported from alternative location"
    fi
fi

# List what was exported
echo ""
echo "Exported files:"
ls -lh "$EXPORT_DIR/" 2>/dev/null || echo "No files exported"

# Copy task timing information
if [ -f /tmp/task_start_time.txt ]; then
    cp /tmp/task_start_time.txt "$EXPORT_DIR/"
fi
if [ -f /tmp/task_end_time.txt ]; then
    cp /tmp/task_end_time.txt "$EXPORT_DIR/"
fi

echo "✅ Export complete"
echo "Reading List data should be available in: $EXPORT_DIR"