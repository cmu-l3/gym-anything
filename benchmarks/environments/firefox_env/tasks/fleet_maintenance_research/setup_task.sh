#!/bin/bash
# Setup script for fleet_maintenance_research

set -e

echo "=== Setting up Fleet Maintenance Research Task ==="

# 1. Kill any existing Firefox instances
pkill -u ga -f firefox 2>/dev/null || true
sleep 1
pkill -9 -u ga -f firefox 2>/dev/null || true

# 2. Clean up previous run artifacts
rm -f /home/ga/Documents/fleet_specs.json
rm -rf /home/ga/Downloads/*

# 3. Setup Firefox Profile (Ensure we know where it is)
# We use the standard profile location logic from the environment
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
    # Fallback: find it
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null)
fi

echo "Using Firefox profile: $PROFILE_DIR"
echo "$PROFILE_DIR" > /tmp/firefox_profile_path

# 4. Record Initial State (Bookmarks)
# We take a snapshot of the bookmarks DB to compare later
if [ -n "$PROFILE_DIR" ] && [ -f "$PROFILE_DIR/places.sqlite" ]; then
    cp "$PROFILE_DIR/places.sqlite" /tmp/places_initial.sqlite
    # Count initial bookmarks
    INITIAL_BOOKMARKS=$(sqlite3 /tmp/places_initial.sqlite "SELECT COUNT(*) FROM moz_bookmarks WHERE type=1;" 2>/dev/null || echo "0")
    echo "$INITIAL_BOOKMARKS" > /tmp/initial_bookmark_count
else
    echo "0" > /tmp/initial_bookmark_count
fi

# 5. Record Task Start Time (Anti-gaming)
date +%s > /tmp/task_start_timestamp

# 6. Launch Firefox
# Start with a neutral page
su - ga -c "DISPLAY=:1 firefox -P default --no-remote 'about:blank' > /tmp/firefox.log 2>&1 &"

# 7. Wait for Firefox Window
echo "Waiting for Firefox..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "firefox"; then
        echo "Firefox started."
        break
    fi
    sleep 1
done

# 8. Maximize Window
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 9. Take Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_start.png 2>/dev/null || true

echo "=== Setup Complete ==="