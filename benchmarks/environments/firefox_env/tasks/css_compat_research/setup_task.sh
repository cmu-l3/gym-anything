#!/bin/bash
# setup_task.sh - Pre-task hook for css_compat_research

set -e
echo "=== Setting up CSS Compatibility Research Task ==="

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# Ensure output directory exists
sudo -u ga mkdir -p /home/ga/Documents

# Remove any existing report file to ensure freshness
rm -f /home/ga/Documents/css_compatibility_report.json
echo "Cleaned up old report files."

# Kill any running Firefox instances to ensure clean DB state
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# Locate Firefox profile
PROFILE_DIR=""
for candidate in \
    "/home/ga/snap/firefox/common/.mozilla/firefox/default.profile" \
    "/home/ga/.mozilla/firefox/default.profile"; do
    if [ -d "$candidate" ]; then
        PROFILE_DIR="$candidate"
        echo "$PROFILE_DIR" > /tmp/firefox_profile_path
        break
    fi
done

if [ -z "$PROFILE_DIR" ]; then
    echo "WARNING: Could not find Firefox profile directory. Creating default..."
    sudo -u ga mkdir -p "/home/ga/.mozilla/firefox/default.profile"
    PROFILE_DIR="/home/ga/.mozilla/firefox/default.profile"
    echo "$PROFILE_DIR" > /tmp/firefox_profile_path
fi

# Clean up specific bookmarks if they exist (to prevent false positives)
PLACES_DB="$PROFILE_DIR/places.sqlite"
if [ -f "$PLACES_DB" ]; then
    echo "Cleaning up existing task-related bookmarks..."
    # Copy DB to temp to avoid locks (though Firefox is killed)
    cp "$PLACES_DB" /tmp/places_setup.sqlite
    
    # Find ID of "CSS Compatibility Research" folder
    FOLDER_ID=$(sqlite3 /tmp/places_setup.sqlite "SELECT id FROM moz_bookmarks WHERE title='CSS Compatibility Research' AND type=2;" 2>/dev/null || echo "")
    
    if [ -n "$FOLDER_ID" ]; then
        # Delete the folder and its children (simple cleanup, might leave orphans in places but acceptable for reset)
        sqlite3 /tmp/places_setup.sqlite "DELETE FROM moz_bookmarks WHERE id=$FOLDER_ID OR parent=$FOLDER_ID;"
        echo "Removed existing bookmark folder."
    fi
    
    # Move modified DB back
    # Note: In a real persistent env, modifying the DB directly is risky, but for ephemeral tasks it's fine.
    # However, to be safe, we often just let the agent create new ones. 
    # For this task, we'll just leave the DB as is to avoid corruption risks, 
    # relying on the timestamp check in export_result.sh to filter old bookmarks if needed.
    rm -f /tmp/places_setup.sqlite
fi

# Launch Firefox with a blank page
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote about:blank > /tmp/firefox.log 2>&1 &"

# Wait for Firefox window
TIMEOUT=30
for i in $(seq 1 $TIMEOUT); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla"; then
        echo "Firefox window detected."
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_start.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_start.png 2>/dev/null || true

echo "=== Setup Complete ==="