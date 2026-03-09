#!/bin/bash
# setup_task.sh - Pre-task hook for state_dept_travel_advisory_research

echo "=== Setting up Travel Advisory Research Task ==="

# 1. Kill Firefox to ensure clean state
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# 2. Record Task Start Time (for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 3. Locate Firefox Profile
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
echo "Using Firefox profile: $PROFILE_DIR"
echo "$PROFILE_DIR" > /tmp/firefox_profile_path.txt

# 4. Record Initial Bookmark State
if [ -f "$PROFILE_DIR/places.sqlite" ]; then
    cp "$PROFILE_DIR/places.sqlite" /tmp/places_initial.sqlite
    INITIAL_BM_COUNT=$(sqlite3 /tmp/places_initial.sqlite "SELECT COUNT(*) FROM moz_bookmarks WHERE type=1;" 2>/dev/null || echo "0")
else
    INITIAL_BM_COUNT=0
fi
echo "$INITIAL_BM_COUNT" > /tmp/initial_bookmark_count.txt

# 5. Clean up any previous output
rm -f /home/ga/Documents/travel_risk_brief.json 2>/dev/null || true
mkdir -p /home/ga/Documents

# 6. Launch Firefox
# Start with blank page to ensure no history pollution
su - ga -c "DISPLAY=:1 firefox -P default --no-remote about:blank > /tmp/firefox.log 2>&1 &"

# 7. Wait for Firefox Window
echo "Waiting for Firefox..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -iE "firefox|mozilla" > /dev/null; then
        echo "Firefox started."
        break
    fi
    sleep 1
done

# 8. Maximize Window
sleep 2
WINDOW_ID=$(DISPLAY=:1 wmctrl -l | grep -iE "firefox|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
fi

# 9. Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="