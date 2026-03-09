#!/bin/bash
# setup_task.sh - Pre-task hook for wayback_web_history_research
set -e

echo "=== Setting up Wayback Web History Research task ==="

# 1. Kill any running Firefox instances to ensure clean state
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# 2. Record Task Start Time (Anti-gaming)
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

# 3. Detect Firefox Profile Directory
PROFILE_DIR=""
# Check common locations
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
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null)
fi
if [ -z "$PROFILE_DIR" ]; then
    echo "WARNING: Could not find Firefox profile. Creating default path for reference."
    PROFILE_DIR="/home/ga/.mozilla/firefox/default.profile"
    mkdir -p "$PROFILE_DIR"
fi
echo "$PROFILE_DIR" > /tmp/firefox_profile_path
echo "Using Firefox profile: $PROFILE_DIR"

# 4. Record Initial Bookmark Count
PLACES_DB="$PROFILE_DIR/places.sqlite"
INITIAL_BOOKMARK_COUNT=0
if [ -f "$PLACES_DB" ]; then
    # Copy DB to avoid locks
    cp "$PLACES_DB" /tmp/places_baseline.sqlite 2>/dev/null || true
    if [ -f /tmp/places_baseline.sqlite ]; then
        INITIAL_BOOKMARK_COUNT=$(sqlite3 /tmp/places_baseline.sqlite \
            "SELECT COUNT(*) FROM moz_bookmarks WHERE type=1;" 2>/dev/null || echo "0")
        rm -f /tmp/places_baseline.sqlite
    fi
fi
echo "$INITIAL_BOOKMARK_COUNT" > /tmp/initial_bookmark_count
echo "Initial bookmarks: $INITIAL_BOOKMARK_COUNT"

# 5. Clean Environment
# Remove previous report if it exists
rm -f /home/ga/Documents/web_history_report.json 2>/dev/null || true
# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# 6. Launch Firefox
echo "Launching Firefox..."
# Start with a blank tab to not bias the agent
su - ga -c "DISPLAY=:1 firefox -P default --no-remote about:blank > /tmp/firefox.log 2>&1 &"

# 7. Wait for Window and Maximize
TIMEOUT=45
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla" > /dev/null 2>&1; then
        echo "Firefox window detected."
        break
    fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done

# Give it a moment to render
sleep 3

# Focus and Maximize
WINDOW_ID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 8. Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="