#!/bin/bash
# setup_task.sh - Pre-task hook for nba_scouting_comparison

set -e
echo "=== Setting up NBA Scouting Comparison Task ==="

# 1. Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 2. Clean up any previous run artifacts
rm -f /home/ga/Documents/nba_comparison.json
rm -f /tmp/nba_task_result.json
echo "Cleaned up previous output files."

# 3. Ensure destination directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# 4. Find Firefox profile directory for later export
# (We don't need to modify it now, just finding it helps verify env is healthy)
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
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null)
fi
echo "Detected Firefox profile: $PROFILE_DIR"
echo "$PROFILE_DIR" > /tmp/firefox_profile_path

# 5. Launch Firefox to a blank page
# Ensure no previous instances are running
pkill -u ga -f firefox 2>/dev/null || true
sleep 2

echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote about:blank > /tmp/firefox.log 2>&1 &"

# 6. Wait for Firefox window and maximize
echo "Waiting for Firefox window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla"; then
        echo "Firefox window detected."
        # Get window ID and maximize
        WID=$(DISPLAY=:1 wmctrl -l | grep -iE "firefox|mozilla" | head -1 | awk '{print $1}')
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz
        DISPLAY=:1 wmctrl -i -a "$WID"
        break
    fi
    sleep 1
done

# 7. Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="