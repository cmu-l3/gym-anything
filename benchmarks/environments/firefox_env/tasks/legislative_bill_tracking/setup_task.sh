#!/bin/bash
# setup_task.sh - Pre-task hook for legislative_bill_tracking

set -e
echo "=== Setting up legislative_bill_tracking task ==="

# 1. Kill any existing Firefox instances to ensure clean DB state
pkill -u ga -f firefox 2>/dev/null || true
sleep 1
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# 2. Record task start timestamp for anti-gaming checks
date +%s > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# 3. Locate Firefox profile
# Try standard locations
PROFILE_DIR=""
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

if [ -z "$PROFILE_DIR" ]; then
    echo "WARNING: Could not find Firefox profile. Firefox might create one on startup."
else
    echo "Found Firefox profile: $PROFILE_DIR"
    echo "$PROFILE_DIR" > /tmp/firefox_profile_path
    
    # Snapshot initial bookmarks to detect changes
    cp "$PROFILE_DIR/places.sqlite" /tmp/places_initial.sqlite 2>/dev/null || true
fi

# 4. Cleanup previous run artifacts
rm -rf /home/ga/Documents/Bills 2>/dev/null || true
rm -f /home/ga/Documents/legislative_report.json 2>/dev/null || true
# Ensure parent directory exists
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Documents

# 5. Launch Firefox
# Start with a blank page or specific URL? Description implies starting from scratch.
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote > /tmp/firefox.log 2>&1 &"

# 6. Wait for Firefox window to ensure it's ready for the agent
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla"; then
        echo "Firefox window detected."
        break
    fi
    sleep 1
done

# 7. Maximize window
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 8. Capture initial screenshot
DISPLAY=:1 scrot /tmp/task_start.png 2>/dev/null || true

echo "=== Setup complete ==="