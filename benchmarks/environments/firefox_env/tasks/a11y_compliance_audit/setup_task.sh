#!/bin/bash
# setup_task.sh - Pre-task hook for a11y_compliance_audit

set -e

echo "=== Setting up a11y_compliance_audit task ==="

# 1. Kill any running Firefox instances to ensure clean state
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# 2. Record Task Start Timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

# 3. Locate Firefox Profile
# We need this to check history later
PROFILE_DIR=""
for candidate in \
    "/home/ga/snap/firefox/common/.mozilla/firefox/default.profile" \
    "/home/ga/.mozilla/firefox/default.profile"; do
    if [ -f "$candidate/places.sqlite" ]; then
        PROFILE_DIR="$candidate"
        break
    fi
done

if [ -z "$PROFILE_DIR" ]; then
    # Fallback search
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null || echo "")
fi

if [ -n "$PROFILE_DIR" ]; then
    echo "$PROFILE_DIR" > /tmp/firefox_profile_path
    echo "Found profile: $PROFILE_DIR"
else
    echo "WARNING: Could not find Firefox profile. verification may be limited."
fi

# 4. Clear previous outputs
mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/accessibility_audit.json
echo "Cleared previous audit files."

# 5. Launch Firefox to blank page
echo "Launching Firefox..."
# Use --new-instance to avoid attaching to any background processes
su - ga -c "DISPLAY=:1 firefox -P default --no-remote about:blank > /tmp/firefox_launch.log 2>&1 &"

# 6. Wait for window
echo "Waiting for Firefox window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla"; then
        echo "Firefox window detected."
        break
    fi
    sleep 1
done

# 7. Maximize window
WINDOW_ID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
fi

# 8. Take Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="