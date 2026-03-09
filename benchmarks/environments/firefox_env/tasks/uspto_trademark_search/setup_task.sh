#!/bin/bash
# setup_task.sh - Pre-task hook for uspto_trademark_search

set -e
echo "=== Setting up USPTO Trademark Search Task ==="

# 1. Kill Firefox to ensure clean state
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# 2. Record Task Start Timestamp (for anti-gaming)
date +%s > /tmp/task_start_timestamp
echo "Task start time: $(cat /tmp/task_start_timestamp)"

# 3. Locate Firefox Profile (to track history/bookmarks later)
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
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null)
fi

# Default if creation failed previously
if [ -z "$PROFILE_DIR" ]; then
    PROFILE_DIR="/home/ga/.mozilla/firefox/default.profile"
fi

echo "$PROFILE_DIR" > /tmp/firefox_profile_path
echo "Using Firefox profile: $PROFILE_DIR"

# 4. Clean up previous artifacts
rm -f /home/ga/Documents/trademark_report.json 2>/dev/null || true
# Ensure directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# 5. Launch Firefox to blank page
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote about:blank > /tmp/firefox.log 2>&1 &"

# 6. Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla"; then
        echo "Firefox window detected."
        break
    fi
    sleep 1
done

# 7. Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 8. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="