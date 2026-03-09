#!/bin/bash
# setup_task.sh - Pre-task hook for federal_pay_research

set -e
echo "=== Setting up federal_pay_research task ==="

# 1. Record task start timestamp for anti-gaming checks
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# 2. Clean up previous run artifacts
rm -f /home/ga/Documents/federal_pay_comparison.json 2>/dev/null || true
sudo -u ga mkdir -p /home/ga/Documents

# 3. Kill existing Firefox instances to ensure clean state
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# 4. Locate Firefox profile (handles standard and Snap installs)
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
echo "$PROFILE_DIR" > /tmp/firefox_profile_path

# 5. Record initial bookmark count
INITIAL_BOOKMARKS=0
if [ -n "$PROFILE_DIR" ] && [ -f "$PROFILE_DIR/places.sqlite" ]; then
    cp "$PROFILE_DIR/places.sqlite" /tmp/places_init.sqlite 2>/dev/null
    INITIAL_BOOKMARKS=$(sqlite3 /tmp/places_init.sqlite "SELECT COUNT(*) FROM moz_bookmarks WHERE type=1;" 2>/dev/null || echo "0")
    rm -f /tmp/places_init.sqlite
fi
echo "$INITIAL_BOOKMARKS" > /tmp/initial_bookmark_count

# 6. Launch Firefox
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote about:blank > /tmp/firefox.log 2>&1 &"

# 7. Wait for Firefox window
echo "Waiting for Firefox..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla" > /dev/null; then
        echo "Firefox window detected."
        break
    fi
    sleep 1
done
sleep 3

# 8. Maximize window
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 9. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="