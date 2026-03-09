#!/bin/bash
# setup_task.sh - Pre-task hook for veterinary_toxicology_triage

set -e

echo "=== Setting up Veterinary Toxicology Triage Task ==="

# 1. Record Task Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task started at: $(cat /tmp/task_start_time.txt)"

# 2. Prepare Output Directory
sudo -u ga mkdir -p /home/ga/Documents
# Remove output file if it exists from previous run
rm -f /home/ga/Documents/feline_triage_report.json

# 3. Clean Firefox State (Kill existing instances)
pkill -u ga -f firefox 2>/dev/null || true
sleep 1
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# 4. Locate Firefox Profile
PROFILE_DIR=""
# Check Snap path
if [ -d "/home/ga/snap/firefox/common/.mozilla/firefox/default.profile" ]; then
    PROFILE_DIR="/home/ga/snap/firefox/common/.mozilla/firefox/default.profile"
# Check standard path
elif [ -d "/home/ga/.mozilla/firefox/default.profile" ]; then
    PROFILE_DIR="/home/ga/.mozilla/firefox/default.profile"
else
    # Fallback search
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs dirname)
fi

echo "$PROFILE_DIR" > /tmp/firefox_profile_path
echo "Using Firefox profile: $PROFILE_DIR"

# 5. Record Initial Bookmark Count (Baseline)
INITIAL_BOOKMARKS=0
if [ -n "$PROFILE_DIR" ] && [ -f "$PROFILE_DIR/places.sqlite" ]; then
    # Copy DB to temp to avoid locks
    cp "$PROFILE_DIR/places.sqlite" /tmp/places_baseline.sqlite
    INITIAL_BOOKMARKS=$(sqlite3 /tmp/places_baseline.sqlite "SELECT COUNT(*) FROM moz_bookmarks WHERE type=1;" 2>/dev/null || echo "0")
    rm -f /tmp/places_baseline.sqlite
fi
echo "$INITIAL_BOOKMARKS" > /tmp/initial_bookmark_count

# 6. Launch Firefox
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote > /tmp/firefox.log 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Firefox" > /dev/null; then
        echo "Firefox window detected."
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Take Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="