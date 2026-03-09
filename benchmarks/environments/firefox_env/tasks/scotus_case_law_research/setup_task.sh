#!/bin/bash
# setup_task.sh - Pre-task hook for scotus_case_law_research
set -e

echo "=== Setting up SCOTUS Research Task ==="

# 1. Kill any existing Firefox instances to ensure clean DB state
pkill -u ga -f firefox 2>/dev/null || true
sleep 1
pkill -9 -u ga -f firefox 2>/dev/null || true

# 2. Locate Firefox Profile
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
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null || echo "")
fi

echo "Using profile: $PROFILE_DIR"
echo "$PROFILE_DIR" > /tmp/firefox_profile_path

# 3. Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 4. Clean up previous artifacts
rm -f /home/ga/Documents/scotus_brief.json 2>/dev/null || true
mkdir -p /home/ga/Documents

# 5. Launch Firefox to blank page
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote about:blank > /tmp/firefox.log 2>&1 &"

# 6. Wait for window
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla" > /dev/null; then
        echo "Firefox window detected."
        break
    fi
    sleep 1
done

# 7. Maximize and focus
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 8. Initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_start.png 2>/dev/null || true

echo "=== Setup Complete ==="