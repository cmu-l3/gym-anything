#!/bin/bash
# setup_task.sh - Pre-task hook for FEC Super PAC Analysis
set -e

echo "=== Setting up FEC Super PAC Analysis task ==="

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# Kill any running Firefox instances to ensure clean state
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# Ensure Documents directory exists for output
sudo -u ga mkdir -p /home/ga/Documents

# Remove any pre-existing output file to prevent false positives
rm -f /home/ga/Documents/super_pac_financials.json 2>/dev/null || true

# Find Firefox profile path (handle both Snap and native installs)
PROFILE_DIR=""
for candidate in \
    "/home/ga/snap/firefox/common/.mozilla/firefox/default.profile" \
    "/home/ga/.mozilla/firefox/default.profile"; do
    if [ -d "$candidate" ]; then
        PROFILE_DIR="$candidate"
        echo "$PROFILE_DIR" > /tmp/firefox_profile_path
        break
    fi
done

if [ -z "$PROFILE_DIR" ]; then
    echo "WARNING: Could not find Firefox profile directory. Creating default structure..."
    mkdir -p /home/ga/.mozilla/firefox/default.profile
    PROFILE_DIR="/home/ga/.mozilla/firefox/default.profile"
    echo "$PROFILE_DIR" > /tmp/firefox_profile_path
fi

# Record initial bookmark count
PLACES_DB="$PROFILE_DIR/places.sqlite"
if [ -f "$PLACES_DB" ]; then
    cp "$PLACES_DB" /tmp/places_baseline.sqlite 2>/dev/null || true
    INITIAL_COUNT=$(sqlite3 /tmp/places_baseline.sqlite \
        "SELECT COUNT(*) FROM moz_bookmarks WHERE type=1;" 2>/dev/null || echo "0")
    echo "$INITIAL_COUNT" > /tmp/initial_bookmark_count
    rm -f /tmp/places_baseline.sqlite
else
    echo "0" > /tmp/initial_bookmark_count
fi

# Launch Firefox
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote about:blank > /tmp/firefox.log 2>&1 &"

# Wait for Firefox window to appear
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla"; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done

# Maximize Firefox window
WINDOW_ID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_start.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_start.png 2>/dev/null || true

echo "=== Setup Complete ==="