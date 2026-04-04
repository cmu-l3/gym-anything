#!/bin/bash
# setup_task.sh - Pre-task hook for nist_cve_audit

set -e
echo "=== Setting up NIST CVE Audit Task ==="

# Record task start timestamp (anti-gaming)
date +%s > /tmp/task_start_timestamp

# Ensure output directory exists
sudo -u ga mkdir -p /home/ga/Documents

# Remove any pre-existing report file
rm -f /home/ga/Documents/cve_audit_report.json

# Kill any existing Firefox instances
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# Locate Firefox profile
PROFILE_DIR=""
for candidate in \
    "/home/ga/snap/firefox/common/.mozilla/firefox/default.profile" \
    "/home/ga/.mozilla/firefox/default.profile"; do
    if [ -f "$candidate/places.sqlite" ]; then
        PROFILE_DIR="$candidate"
        break
    fi
done

# If not found, try dynamic search
if [ -z "$PROFILE_DIR" ]; then
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null || echo "")
fi

# Save profile path for export script
echo "$PROFILE_DIR" > /tmp/firefox_profile_path

# Record initial bookmark state (to detect new bookmarks later)
INITIAL_BM_COUNT=0
if [ -n "$PROFILE_DIR" ] && [ -f "$PROFILE_DIR/places.sqlite" ]; then
    cp "$PROFILE_DIR/places.sqlite" /tmp/places_init.sqlite
    INITIAL_BM_COUNT=$(sqlite3 /tmp/places_init.sqlite "SELECT COUNT(*) FROM moz_bookmarks WHERE type=1;" 2>/dev/null || echo "0")
    rm -f /tmp/places_init.sqlite
fi
echo "$INITIAL_BM_COUNT" > /tmp/initial_bookmark_count

# Launch Firefox (starts with blank page per env config)
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote > /tmp/firefox.log 2>&1 &"

# Wait for Firefox window
TIMEOUT=45
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla" > /dev/null 2>&1; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done

# Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_start.png 2>/dev/null || true

echo "=== Setup Complete ==="