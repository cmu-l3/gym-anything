#!/bin/bash
# setup_task.sh - Pre-task hook for OFAC Sanctions Compliance Screening

set -e
echo "=== Setting up OFAC Sanctions Compliance Task ==="

# 1. Record Task Start Time (for anti-gaming file freshness checks)
date +%s > /tmp/task_start_timestamp
echo "Task start time: $(cat /tmp/task_start_timestamp)"

# 2. Clean Environment
# Kill running Firefox instances
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# Remove any previous report files
rm -f /home/ga/Documents/sanctions_audit.json 2>/dev/null || true

# Ensure output directory exists
sudo -u ga mkdir -p /home/ga/Documents

# 3. Identify Firefox Profile
# We need to know where places.sqlite is to check bookmarks/history later
PROFILE_DIR=""
# Check common locations
for candidate in \
    "/home/ga/snap/firefox/common/.mozilla/firefox/default.profile" \
    "/home/ga/.mozilla/firefox/default.profile"; do
    if [ -f "$candidate/places.sqlite" ]; then
        PROFILE_DIR="$candidate"
        break
    fi
done

# Fallback search
if [ -z "$PROFILE_DIR" ]; then
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null || echo "")
fi

echo "$PROFILE_DIR" > /tmp/firefox_profile_path
echo "Detected Firefox profile: $PROFILE_DIR"

# 4. Record Initial Bookmark State (Baseline)
INITIAL_BM_COUNT=0
if [ -n "$PROFILE_DIR" ] && [ -f "$PROFILE_DIR/places.sqlite" ]; then
    # Copy DB to temp to avoid locks
    cp "$PROFILE_DIR/places.sqlite" /tmp/places_baseline.sqlite 2>/dev/null || true
    if [ -f /tmp/places_baseline.sqlite ]; then
        INITIAL_BM_COUNT=$(sqlite3 /tmp/places_baseline.sqlite "SELECT COUNT(*) FROM moz_bookmarks WHERE type=1;" 2>/dev/null || echo "0")
        rm -f /tmp/places_baseline.sqlite
    fi
fi
echo "$INITIAL_BM_COUNT" > /tmp/initial_bookmark_count
echo "Initial bookmark count: $INITIAL_BM_COUNT"

# 5. Launch Firefox
echo "Launching Firefox..."
# Use su to run as user 'ga', export display, run in background
su - ga -c "DISPLAY=:1 firefox -P default --no-remote > /tmp/firefox.log 2>&1 &"

# Wait for Firefox window to appear
echo "Waiting for Firefox window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla" > /dev/null; then
        echo "Firefox window detected."
        break
    fi
    sleep 1
done

# Maximize the window
sleep 2
WINDOW_ID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
fi

# 6. Capture Initial Screenshot
DISPLAY=:1 scrot /tmp/task_start.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_start.png 2>/dev/null || true

echo "=== Setup Complete ==="