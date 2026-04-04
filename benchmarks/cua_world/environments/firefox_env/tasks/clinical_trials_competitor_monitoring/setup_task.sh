#!/bin/bash
# setup_task.sh - Pre-task hook for clinical_trials_competitor_monitoring
set -e

echo "=== Setting up Clinical Trials Competitor Monitoring task ==="

# 1. Kill Firefox to ensure clean state
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# 2. Record Task Start Time (Anti-gaming)
date +%s > /tmp/task_start_timestamp.txt

# 3. Locate Firefox Profile
# (Check standard locations)
PROFILE_DIR=""
for candidate in \
    "/home/ga/snap/firefox/common/.mozilla/firefox/default.profile" \
    "/home/ga/.mozilla/firefox/default.profile"; do
    if [ -f "$candidate/places.sqlite" ]; then
        PROFILE_DIR="$candidate"
        break
    fi
done

# Fallback search if specific paths fail
if [ -z "$PROFILE_DIR" ]; then
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null || echo "/home/ga/.mozilla/firefox/default.profile")
fi

echo "Using Firefox profile: $PROFILE_DIR"
echo "$PROFILE_DIR" > /tmp/firefox_profile_path.txt

# 4. Clear/Reset State
# Remove the output file if it exists from a previous run
rm -f /home/ga/Documents/trial_intelligence.json

# Record initial bookmark count (baseline)
PLACES_DB="$PROFILE_DIR/places.sqlite"
INITIAL_BM_COUNT=0
if [ -f "$PLACES_DB" ]; then
    # Create a temp copy to read without locking
    cp "$PLACES_DB" /tmp/places_baseline.sqlite 2>/dev/null || true
    INITIAL_BM_COUNT=$(sqlite3 /tmp/places_baseline.sqlite "SELECT COUNT(*) FROM moz_bookmarks WHERE type=1;" 2>/dev/null || echo "0")
    rm -f /tmp/places_baseline.sqlite
fi
echo "$INITIAL_BM_COUNT" > /tmp/initial_bookmark_count.txt

# 5. Ensure Directories Exist
sudo -u ga mkdir -p /home/ga/Documents /home/ga/Downloads

# 6. Launch Firefox
# Start with a blank page or the ClinicalTrials.gov home page?
# Task description says "Navigate to...", so starting blank is fine/better.
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote about:blank > /tmp/firefox.log 2>&1 &"

# 7. Wait for Window
echo "Waiting for Firefox window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -iE "firefox|mozilla" > /dev/null; then
        echo "Firefox window detected."
        break
    fi
    sleep 1
done

# Allow UI to stabilize
sleep 3

# Maximize
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 8. Take Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="