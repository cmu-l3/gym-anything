#!/bin/bash
# setup_task.sh - Pre-task hook for open_data_government_spending_research

echo "=== Setting up open_data_government_spending_research ==="

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# Kill any running Firefox to get clean state
pkill -u ga -f firefox 2>/dev/null || true
sleep 2

# Find Firefox profile
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
    echo "WARNING: Could not find Firefox profile directory"
else
    echo "Firefox profile: $PROFILE_DIR"
fi

# Record initial bookmark count as baseline
PLACES_DB="$PROFILE_DIR/places.sqlite"
INITIAL_BOOKMARKS=0
if [ -f "$PLACES_DB" ]; then
    TEMP_DB="/tmp/places_spending_setup_$$.sqlite"
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null
    if [ -f "$TEMP_DB" ]; then
        INITIAL_BOOKMARKS=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(*) FROM moz_bookmarks WHERE type=1;" 2>/dev/null || echo "0")
        rm -f "$TEMP_DB"
    fi
fi
echo "$INITIAL_BOOKMARKS" > /tmp/initial_bookmark_count
echo "Initial bookmark count: $INITIAL_BOOKMARKS"

# Count initial Downloads CSVs as baseline
INITIAL_CSVS=$(find /home/ga/Downloads -maxdepth 2 -name "*.csv" 2>/dev/null | wc -l)
echo "$INITIAL_CSVS" > /tmp/initial_csv_count
echo "Initial CSV count in Downloads: $INITIAL_CSVS"

# Remove any pre-existing output files to ensure freshness
rm -f /home/ga/Documents/dod_spending_research.txt
echo "Cleared previous dod_spending_research.txt (if any)"

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
mkdir -p /home/ga/Downloads

# Launch Firefox
DISPLAY=:1 firefox --new-instance --profile "$PROFILE_DIR" 2>/dev/null &
sleep 4

# Wait for Firefox window
for i in $(seq 1 10); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla"; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_start_screenshot.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Setup Complete ==="
