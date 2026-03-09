#!/bin/bash
# setup_task.sh - Pre-task hook for crypto_energy_research

set -e
echo "=== Setting up crypto_energy_research task ==="

# 1. Kill existing Firefox instances to ensure clean state and unlocked DB
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# 2. Locate Firefox Profile
# Check standard locations (Snap vs Apt)
PROFILE_DIR=""
for candidate in \
    "/home/ga/snap/firefox/common/.mozilla/firefox/default.profile" \
    "/home/ga/.mozilla/firefox/default.profile"; do
    if [ -d "$candidate" ]; then
        PROFILE_DIR="$candidate"
        break
    fi
done

# Fallback search
if [ -z "$PROFILE_DIR" ]; then
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null)
fi

if [ -z "$PROFILE_DIR" ]; then
    echo "WARNING: Could not find Firefox profile. Task may fail verification."
    # Create a default path just in case it's created on launch
    PROFILE_DIR="/home/ga/.mozilla/firefox/default.profile"
fi

echo "$PROFILE_DIR" > /tmp/firefox_profile_path
echo "Using Firefox profile at: $PROFILE_DIR"

# 3. Record Initial State (Bookmarks)
PLACES_DB="$PROFILE_DIR/places.sqlite"
INITIAL_BM_COUNT=0
if [ -f "$PLACES_DB" ]; then
    # Copy DB to temp to avoid locks
    cp "$PLACES_DB" /tmp/places_init.sqlite
    INITIAL_BM_COUNT=$(sqlite3 /tmp/places_init.sqlite "SELECT COUNT(*) FROM moz_bookmarks WHERE type=1;" 2>/dev/null || echo "0")
    rm -f /tmp/places_init.sqlite
fi
echo "$INITIAL_BM_COUNT" > /tmp/initial_bookmark_count

# 4. Clean up previous run artifacts
rm -f /home/ga/Documents/crypto_environmental_brief.json
rm -f /home/ga/Downloads/*.pdf
mkdir -p /home/ga/Documents
mkdir -p /home/ga/Downloads
chown -R ga:ga /home/ga/Documents /home/ga/Downloads

# 5. Record Start Time (Anti-Gaming)
date +%s > /tmp/task_start_time
echo "Task started at: $(cat /tmp/task_start_time)"

# 6. Launch Firefox
# Start with a blank page or specific search engine page
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote about:blank > /tmp/firefox.log 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -iE "firefox|mozilla"; then
        echo "Firefox window detected."
        break
    fi
    sleep 1
done

# Focus and maximize
WID=$(DISPLAY=:1 wmctrl -l | grep -iE "firefox|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -a "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz
fi

# 7. Take Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="