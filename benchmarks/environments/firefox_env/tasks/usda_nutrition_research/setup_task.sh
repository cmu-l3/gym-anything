#!/bin/bash
# setup_task.sh - Pre-task hook for usda_nutrition_research

set -e
echo "=== Setting up USDA Nutrition Research task ==="

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# 2. Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# 3. Clean up any previous runs
rm -f /home/ga/Documents/nutrition_reference.json 2>/dev/null || true

# 4. Handle Firefox Profile (Find places.sqlite)
PROFILE_DIR=""
for candidate in \
    "/home/ga/snap/firefox/common/.mozilla/firefox/default.profile" \
    "/home/ga/.mozilla/firefox/default.profile"; do
    if [ -f "$candidate/places.sqlite" ]; then
        PROFILE_DIR="$candidate"
        break
    fi
done

# Fallback search if standard paths fail
if [ -z "$PROFILE_DIR" ]; then
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null)
fi

# Save profile path for export script
if [ -n "$PROFILE_DIR" ]; then
    echo "$PROFILE_DIR" > /tmp/firefox_profile_path.txt
    echo "Using Firefox profile: $PROFILE_DIR"
    
    # Record initial bookmark count
    cp "$PROFILE_DIR/places.sqlite" /tmp/places_initial.sqlite
    INITIAL_BM_COUNT=$(sqlite3 /tmp/places_initial.sqlite "SELECT COUNT(*) FROM moz_bookmarks WHERE type=1;" 2>/dev/null || echo "0")
    echo "$INITIAL_BM_COUNT" > /tmp/initial_bookmark_count.txt
    rm -f /tmp/places_initial.sqlite
else
    echo "WARNING: Could not find Firefox profile. History/Bookmark verification may be limited."
    echo "0" > /tmp/initial_bookmark_count.txt
fi

# 5. Launch Firefox
echo "Launching Firefox..."
# Kill any existing instances first
pkill -u ga -f firefox 2>/dev/null || true
sleep 2

# Start Firefox detached
su - ga -c "DISPLAY=:1 firefox -P default --no-remote https://fdc.nal.usda.gov/ > /tmp/firefox.log 2>&1 &"

# 6. Wait for Firefox to appear
echo "Waiting for Firefox window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -iE "firefox|mozilla" > /dev/null; then
        echo "Firefox window detected."
        break
    fi
    sleep 1
done

# 7. Maximize and focus
sleep 3
WID=$(DISPLAY=:1 wmctrl -l | grep -iE "firefox|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# 8. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="