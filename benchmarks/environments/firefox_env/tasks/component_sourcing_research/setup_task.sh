#!/bin/bash
# setup_task.sh - Pre-task hook for component_sourcing_research

set -e
echo "=== Setting up component_sourcing_research task ==="

# 1. Record Task Start Time
date +%s > /tmp/task_start_timestamp

# 2. Clean previous session
echo "Killing Firefox..."
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# 3. Clean output artifacts
echo "Cleaning artifacts..."
rm -f /home/ga/Documents/bom_report.json 2>/dev/null || true
rm -f /home/ga/Documents/NE555P_datasheet.pdf 2>/dev/null || true
# Clean downloads to prevent confusion
rm -f /home/ga/Downloads/*.pdf 2>/dev/null || true

# 4. Ensure directories exist
sudo -u ga mkdir -p /home/ga/Documents
sudo -u ga mkdir -p /home/ga/Downloads

# 5. Identify Profile for Verification Baseline
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

# Record initial bookmark count
INITIAL_BOOKMARK_COUNT=0
if [ -n "$PROFILE_DIR" ] && [ -f "$PROFILE_DIR/places.sqlite" ]; then
    cp "$PROFILE_DIR/places.sqlite" /tmp/places_baseline.sqlite
    INITIAL_BOOKMARK_COUNT=$(sqlite3 /tmp/places_baseline.sqlite "SELECT COUNT(*) FROM moz_bookmarks WHERE type=1;" 2>/dev/null || echo "0")
    rm -f /tmp/places_baseline.sqlite
fi
echo "$INITIAL_BOOKMARK_COUNT" > /tmp/initial_bookmark_count

# 6. Launch Firefox
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote about:blank > /tmp/firefox.log 2>&1 &"

# Wait for window
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Firefox" > /dev/null; then
        echo "Firefox window detected."
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="