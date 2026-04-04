#!/bin/bash
# setup_task.sh - Pre-task hook for archive_audio_research_curation

set -e

echo "=== Setting up archive_audio_research_curation task ==="

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# 1. Clean up previous run artifacts
echo "Cleaning up previous artifacts..."
rm -rf /home/ga/Documents/FDR_Audio
# Create parent Documents folder if it doesn't exist
sudo -u ga mkdir -p /home/ga/Documents
sudo -u ga mkdir -p /home/ga/Downloads

# 2. Kill any existing Firefox instances to ensure clean state
echo "Killing existing Firefox instances..."
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# 3. Find Firefox profile (for history tracking later)
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

if [ -n "$PROFILE_DIR" ]; then
    echo "Found Firefox profile: $PROFILE_DIR"
    echo "$PROFILE_DIR" > /tmp/firefox_profile_path
else
    echo "WARNING: Could not find Firefox profile. History verification might be limited."
fi

# 4. Launch Firefox
echo "Launching Firefox..."
# Start with a blank page or a neutral start page
su - ga -c "DISPLAY=:1 firefox -P default --no-remote about:blank > /tmp/firefox.log 2>&1 &"

# 5. Wait for Firefox to be ready
echo "Waiting for Firefox window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -iE "firefox|mozilla" > /dev/null; then
        echo "Firefox window detected."
        break
    fi
    sleep 1
done

# 6. Maximize window
WINDOW_ID=$(DISPLAY=:1 wmctrl -l | grep -iE "firefox|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    echo "Maximizing window $WINDOW_ID..."
    DISPLAY=:1 wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    # Focus
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
fi

# 7. Take initial screenshot
sleep 2
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="