#!/bin/bash
# setup_task.sh - Pre-task hook for PubChem Chemical Hazard Research

set -e
echo "=== Setting up PubChem Chemical Hazard Research Task ==="

# 1. Record Task Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# 2. Cleanup Previous State
# Kill Firefox to ensure clean database state
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true

# Remove output file if it exists
rm -f /home/ga/Documents/chemical_hazard_summary.json
echo "Cleaned up previous output files."

# Ensure Documents directory exists
sudo -u ga mkdir -p /home/ga/Documents

# 3. Locate Firefox Profile
# We need this to check initial bookmark state
PROFILE_DIR=""
# Check Snap path
if [ -d "/home/ga/snap/firefox/common/.mozilla/firefox/default.profile" ]; then
    PROFILE_DIR="/home/ga/snap/firefox/common/.mozilla/firefox/default.profile"
# Check standard path
elif [ -d "/home/ga/.mozilla/firefox/default.profile" ]; then
    PROFILE_DIR="/home/ga/.mozilla/firefox/default.profile"
else
    # Fallback search
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null)
fi

echo "Using Firefox profile: $PROFILE_DIR"
echo "$PROFILE_DIR" > /tmp/firefox_profile_path

# 4. Record Initial Bookmark Count
PLACES_DB="$PROFILE_DIR/places.sqlite"
INITIAL_BM_COUNT=0

if [ -f "$PLACES_DB" ]; then
    # Copy DB to temp to avoid locks
    cp "$PLACES_DB" /tmp/places_initial.sqlite 2>/dev/null
    INITIAL_BM_COUNT=$(sqlite3 /tmp/places_initial.sqlite "SELECT COUNT(*) FROM moz_bookmarks WHERE type=1;" 2>/dev/null || echo "0")
    rm -f /tmp/places_initial.sqlite
fi
echo "$INITIAL_BM_COUNT" > /tmp/initial_bookmark_count
echo "Initial bookmark count: $INITIAL_BM_COUNT"

# 5. Launch Firefox
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote > /tmp/firefox.log 2>&1 &"

# Wait for Firefox window
echo "Waiting for Firefox window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla"; then
        echo "Firefox window detected."
        break
    fi
    sleep 1
done

# Maximize Window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 6. Capture Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="