#!/bin/bash
# setup_task.sh - Pre-task hook for NIST Research Task

set -e
echo "=== Setting up NIST Thermophysical Properties Research ==="

# 1. Record Task Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 2. Cleanup previous runs
rm -f /home/ga/Documents/fluid_properties.json 2>/dev/null || true
# Ensure output directory exists
sudo -u ga mkdir -p /home/ga/Documents

# 3. Kill Firefox to ensure clean state
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# 4. Locate Firefox Profile
# (Logic to handle both standard and Snap installations common in Ubuntu envs)
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

if [ -z "$PROFILE_DIR" ]; then
    echo "WARNING: Could not find Firefox profile. Automation might be unstable."
else
    echo "Found Firefox profile: $PROFILE_DIR"
    echo "$PROFILE_DIR" > /tmp/firefox_profile_path.txt
    
    # Snapshot initial bookmark state
    PLACES_DB="$PROFILE_DIR/places.sqlite"
    cp "$PLACES_DB" /tmp/places_baseline.sqlite 2>/dev/null || true
fi

# 5. Launch Firefox
# Start with a blank page or NIST home page? Task says "Starting State: Firefox is open to a blank page."
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote about:blank > /tmp/firefox_launch.log 2>&1 &"

# 6. Wait for Window
echo "Waiting for Firefox window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -iE "firefox|mozilla"; then
        echo "Firefox window detected."
        break
    fi
    sleep 1
done

# 7. Maximize Window
WINDOW_ID=$(DISPLAY=:1 wmctrl -l | grep -iE "firefox|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
fi

# 8. Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="