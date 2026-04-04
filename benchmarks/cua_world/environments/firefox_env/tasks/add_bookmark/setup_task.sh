#!/bin/bash
# setup_task.sh - Pre-task hook for add_bookmark task
# Prepares Firefox environment for bookmark addition

set -e

echo "=== Setting up add_bookmark task ==="

# Source utilities if available
if [ -f "/workspace/utils/task_utils.sh" ]; then
    source /workspace/utils/task_utils.sh
fi

# Kill any existing Firefox instances
echo "Killing any existing Firefox instances..."
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# Get profile path - check both regular and Snap Firefox locations
SNAP_PROFILE_DIR="/home/ga/snap/firefox/common/.mozilla/firefox/default.profile"
REGULAR_PROFILE_DIR="/home/ga/.mozilla/firefox/default.profile"

if [ -f "$SNAP_PROFILE_DIR/places.sqlite" ]; then
    PROFILE_DIR="$SNAP_PROFILE_DIR"
    echo "Using Snap Firefox profile: $PROFILE_DIR"
elif [ -f "$REGULAR_PROFILE_DIR/places.sqlite" ]; then
    PROFILE_DIR="$REGULAR_PROFILE_DIR"
    echo "Using regular Firefox profile: $PROFILE_DIR"
else
    # Try to find it dynamically
    FOUND_DB=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1)
    if [ -n "$FOUND_DB" ]; then
        PROFILE_DIR=$(dirname "$FOUND_DB")
        echo "Found Firefox profile at: $PROFILE_DIR"
    else
        PROFILE_DIR="$REGULAR_PROFILE_DIR"
        echo "WARNING: Could not find places.sqlite, defaulting to: $PROFILE_DIR"
    fi
fi

# Count existing bookmarks before task
PLACES_DB="$PROFILE_DIR/places.sqlite"
INITIAL_BOOKMARK_COUNT=0
if [ -f "$PLACES_DB" ]; then
    # Copy DB to avoid lock issues
    cp "$PLACES_DB" /tmp/places_initial.sqlite 2>/dev/null || true
    INITIAL_BOOKMARK_COUNT=$(sqlite3 /tmp/places_initial.sqlite "SELECT COUNT(*) FROM moz_bookmarks WHERE type = 1;" 2>/dev/null || echo "0")
    rm -f /tmp/places_initial.sqlite
fi
echo "Initial bookmark count: $INITIAL_BOOKMARK_COUNT"
echo "$INITIAL_BOOKMARK_COUNT" > /tmp/initial_bookmark_count

# Check if wikipedia.org is already bookmarked
WIKIPEDIA_ALREADY_BOOKMARKED="false"
if [ -f "$PLACES_DB" ]; then
    cp "$PLACES_DB" /tmp/places_check.sqlite 2>/dev/null || true
    EXISTING=$(sqlite3 /tmp/places_check.sqlite "SELECT COUNT(*) FROM moz_bookmarks b JOIN moz_places p ON b.fk = p.id WHERE b.type = 1 AND p.url LIKE '%wikipedia.org%';" 2>/dev/null || echo "0")
    rm -f /tmp/places_check.sqlite
    if [ "$EXISTING" -gt 0 ]; then
        WIKIPEDIA_ALREADY_BOOKMARKED="true"
        echo "WARNING: Wikipedia already bookmarked. Count: $EXISTING"
    fi
fi
echo "$WIKIPEDIA_ALREADY_BOOKMARKED" > /tmp/wikipedia_already_bookmarked

# Ensure Downloads directory exists
sudo -u ga mkdir -p /home/ga/Downloads

# Create task info file for reference
cat > /home/ga/TASK_INFO.txt << 'EOF'
TASK: Add Bookmark

Your task is to add Wikipedia as a bookmark in Firefox.

Steps:
1. Open Firefox (it may already be open)
2. Navigate to https://www.wikipedia.org
3. Add the page as a bookmark using:
   - Press Ctrl+D, OR
   - Click the star icon in the address bar, OR
   - Use Bookmarks menu -> Bookmark This Page

The bookmark should be saved successfully.
EOF
chown ga:ga /home/ga/TASK_INFO.txt

# Launch Firefox (starts with blank page per profile settings)
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote > /tmp/firefox.log 2>&1 &"

# Wait for Firefox to start
echo "Waiting for Firefox to start..."
TIMEOUT=30
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if pgrep -u ga -f firefox > /dev/null; then
        echo "Firefox process started after ${ELAPSED}s"
        break
    fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done

# Wait for Firefox window to appear
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla"; then
        echo "Firefox window appeared after ${ELAPSED}s"
        break
    fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done

# Give Firefox a moment to fully initialize
sleep 3

# Focus Firefox window
WINDOW_ID=$(DISPLAY=:1 wmctrl -l | grep -iE "firefox|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
    echo "Focused Firefox window: $WINDOW_ID"
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_start.png 2>/dev/null || true

echo "=== add_bookmark task setup complete ==="
echo "Firefox is running. Ready for agent to navigate to wikipedia.org and add bookmark."
