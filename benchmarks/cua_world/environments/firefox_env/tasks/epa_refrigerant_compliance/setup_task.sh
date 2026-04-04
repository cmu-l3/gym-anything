#!/bin/bash
# setup_task.sh - Pre-task hook for EPA Refrigerant Compliance Research

set -e

echo "=== Setting up EPA Refrigerant Compliance Research ==="

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task started at: $(cat /tmp/task_start_time.txt)"

# 2. Ensure Documents directory exists for output
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# 3. Clean up any previous attempts
rm -f /home/ga/Documents/refrigerant_compliance_guide.json

# 4. Handle Firefox Profile (Locate or Create)
# We need to find the profile to track bookmarks/history later
PROFILE_DIR=""
# Check common locations
for candidate in \
    "/home/ga/snap/firefox/common/.mozilla/firefox/default.profile" \
    "/home/ga/.mozilla/firefox/default.profile"; do
    if [ -d "$candidate" ]; then
        PROFILE_DIR="$candidate"
        break
    fi
done

if [ -z "$PROFILE_DIR" ]; then
    # Fallback search
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null || echo "")
fi

echo "Using Firefox profile at: $PROFILE_DIR"
echo "$PROFILE_DIR" > /tmp/firefox_profile_path.txt

# 5. Launch Firefox with a clean slate (blank page)
# Kill existing instances first
pkill -u ga -f firefox || true
sleep 2
pkill -9 -u ga -f firefox || true
sleep 1

echo "Launching Firefox..."
# Start Firefox in background, directed to about:blank or a neutral page
su - ga -c "DISPLAY=:1 firefox --new-window about:blank > /dev/null 2>&1 &"

# 6. Wait for Firefox window to appear
echo "Waiting for Firefox window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Firefox" > /dev/null; then
        echo "Firefox window detected."
        break
    fi
    sleep 1
done

# 7. Maximize Firefox window
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# 8. Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="