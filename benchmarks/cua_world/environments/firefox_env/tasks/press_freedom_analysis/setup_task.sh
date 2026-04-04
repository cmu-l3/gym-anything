#!/bin/bash
# setup_task.sh - Pre-task hook for press_freedom_analysis

set -e
echo "=== Setting up press_freedom_analysis task ==="

# 1. Record task start timestamp for anti-gaming (file freshness check)
date +%s > /tmp/task_start_timestamp
echo "Task start time: $(cat /tmp/task_start_timestamp)"

# 2. Kill any running Firefox instances to ensure clean state
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# 3. Locate Firefox profile (handle PPA vs Snap paths)
PROFILE_DIR=""
# Check standard PPA/Apt location first (preferred in this env)
if [ -d "/home/ga/.mozilla/firefox" ]; then
    # Find the profile directory containing places.sqlite
    PROFILE_DIR=$(find /home/ga/.mozilla/firefox -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null)
fi
# Fallback to Snap path if not found
if [ -z "$PROFILE_DIR" ] && [ -d "/home/ga/snap/firefox/common/.mozilla/firefox" ]; then
    PROFILE_DIR=$(find /home/ga/snap/firefox/common/.mozilla/firefox -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null)
fi

# If still not found, just default to the default profile path structure
if [ -z "$PROFILE_DIR" ]; then
    PROFILE_DIR="/home/ga/.mozilla/firefox/default.profile"
fi

echo "Detected Firefox profile: $PROFILE_DIR"
echo "$PROFILE_DIR" > /tmp/firefox_profile_path

# 4. Clean up previous artifacts
rm -f /home/ga/Documents/press_freedom_comparison.json 2>/dev/null || true
rm -f /home/ga/Documents/press_freedom.json 2>/dev/null || true  # Common misnaming
mkdir -p /home/ga/Documents

# 5. Record initial bookmark count (baseline)
INITIAL_BOOKMARKS=0
if [ -f "$PROFILE_DIR/places.sqlite" ]; then
    # Copy DB to temp to avoid locks
    cp "$PROFILE_DIR/places.sqlite" /tmp/places_baseline.sqlite 2>/dev/null || true
    if [ -f "/tmp/places_baseline.sqlite" ]; then
        INITIAL_BOOKMARKS=$(sqlite3 /tmp/places_baseline.sqlite "SELECT COUNT(*) FROM moz_bookmarks WHERE type=1;" 2>/dev/null || echo "0")
        rm -f /tmp/places_baseline.sqlite
    fi
fi
echo "$INITIAL_BOOKMARKS" > /tmp/initial_bookmark_count
echo "Initial bookmark count: $INITIAL_BOOKMARKS"

# 6. Launch Firefox
# Use --new-instance to ensure it doesn't attach to a background process
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote about:blank > /tmp/firefox.log 2>&1 &"

# 7. Wait for window to ensure agent sees open browser
echo "Waiting for Firefox window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla" > /dev/null; then
        echo "Firefox window detected."
        break
    fi
    sleep 1
done

# Maximize the window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 8. Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_start.png 2>/dev/null || true

echo "=== Setup complete ==="