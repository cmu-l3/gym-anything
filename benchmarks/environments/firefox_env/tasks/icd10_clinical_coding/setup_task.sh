#!/bin/bash
# setup_task.sh - Pre-task hook for icd10_clinical_coding

set -e
echo "=== Setting up ICD-10 Clinical Coding Task ==="

# 1. Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# 2. Clean up any previous run artifacts
rm -f /home/ga/Documents/icd10_coding_sheet.json
rm -f /tmp/task_result.json

# 3. Ensure Documents directory exists
sudo -u ga mkdir -p /home/ga/Documents

# 4. Prepare Firefox Profile
# Kill any running Firefox instances to ensure clean DB access
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true

# Find the profile directory
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
echo "$PROFILE_DIR" > /tmp/firefox_profile_path

# 5. Record Initial State (Bookmark Count)
INITIAL_BM_COUNT=0
if [ -n "$PROFILE_DIR" ] && [ -f "$PROFILE_DIR/places.sqlite" ]; then
    # Copy DB to temp to avoid lock
    cp "$PROFILE_DIR/places.sqlite" /tmp/places_init.sqlite
    INITIAL_BM_COUNT=$(sqlite3 /tmp/places_init.sqlite "SELECT COUNT(*) FROM moz_bookmarks WHERE type=1;" 2>/dev/null || echo "0")
    rm -f /tmp/places_init.sqlite
fi
echo "$INITIAL_BM_COUNT" > /tmp/initial_bookmark_count

# 6. Launch Firefox
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote about:blank > /tmp/firefox.log 2>&1 &"

# 7. Wait for window and maximize
echo "Waiting for Firefox window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -iE "firefox|mozilla"; then
        echo "Firefox window detected."
        break
    fi
    sleep 1
done
sleep 2

# Maximize
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 8. Capture initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="