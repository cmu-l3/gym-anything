#!/bin/bash
# setup_task.sh - Pre-task hook for FCC License Audit
set -e

echo "=== Setting up FCC License Audit task ==="

# Record task start timestamp for anti-gaming (file freshness check)
date +%s > /tmp/task_start_timestamp
echo "Task start time: $(cat /tmp/task_start_timestamp)"

# Kill any running Firefox instances to ensure clean database state
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# Find Firefox profile directory
PROFILE_DIR=""
# Check Snap path first (Ubuntu default)
if [ -d "/home/ga/snap/firefox/common/.mozilla/firefox" ]; then
    PROFILE_DIR=$(find /home/ga/snap/firefox/common/.mozilla/firefox -name "*.default*" -type d | head -n 1)
fi
# Fallback to standard path
if [ -z "$PROFILE_DIR" ]; then
    PROFILE_DIR=$(find /home/ga/.mozilla/firefox -name "*.default*" -type d | head -n 1)
fi

echo "Using Firefox profile: $PROFILE_DIR"
echo "$PROFILE_DIR" > /tmp/firefox_profile_path

# Record initial bookmark state (to detect changes)
PLACES_DB="$PROFILE_DIR/places.sqlite"
INITIAL_BOOKMARKS=0
if [ -f "$PLACES_DB" ]; then
    # Copy DB to temp to avoid locks
    cp "$PLACES_DB" /tmp/places_baseline.sqlite
    INITIAL_BOOKMARKS=$(sqlite3 /tmp/places_baseline.sqlite "SELECT COUNT(*) FROM moz_bookmarks WHERE type=1;" 2>/dev/null || echo "0")
    rm -f /tmp/places_baseline.sqlite
fi
echo "$INITIAL_BOOKMARKS" > /tmp/initial_bookmark_count
echo "Initial bookmark count: $INITIAL_BOOKMARKS"

# Ensure Documents directory exists and is clean
mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/fcc_license_audit.json

# Launch Firefox to a clean starting state
echo "Launching Firefox..."
# Use su to run as user 'ga'
su - ga -c "DISPLAY=:1 firefox -P default --no-remote 'about:blank' > /tmp/firefox.log 2>&1 &"

# Wait for Firefox window to appear
echo "Waiting for Firefox window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "firefox" > /dev/null; then
        echo "Firefox started."
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_start.png 2>/dev/null || true

echo "=== Setup complete ==="