#!/bin/bash
set -e
echo "=== Setting up import_incident_log_csv task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Ensure Nx Server is running and cameras are ready
# (Using utility function from env setup, but re-verifying here)
wait_for_cameras > /dev/null 2>&1 || true

# Refresh token for setup operations
TOKEN=$(get_nx_token)

# Record initial bookmark count to detect changes
# iterate all cameras and sum bookmarks
echo "Counting initial bookmarks..."
INITIAL_BOOKMARK_COUNT=0
DEVICES=$(nx_api_get "/rest/v1/devices" | python3 -c "import sys,json; print(' '.join([d['id'] for d in json.load(sys.stdin)]))" 2>/dev/null || echo "")

for dev_id in $DEVICES; do
    COUNT=$(nx_api_get "/rest/v1/devices/${dev_id}/bookmarks" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
    INITIAL_BOOKMARK_COUNT=$((INITIAL_BOOKMARK_COUNT + COUNT))
done
echo "$INITIAL_BOOKMARK_COUNT" > /tmp/initial_bookmark_count.txt
echo "Initial bookmarks: $INITIAL_BOOKMARK_COUNT"

# Generate Dynamic CSV Data
# We create events relative to NOW so they appear on the timeline at valid times
echo "Generating CSV data..."
mkdir -p /home/ga/Documents

CSV_FILE="/home/ga/Documents/acs_exceptions.csv"
echo "Timestamp,Camera Name,Event Type,User,Duration_Sec" > "$CSV_FILE"

NOW=$(date +%s)

# Event 1: Entrance Camera - Door Held Open - 1 hour ago
T1=$(date -d @$((NOW - 3600)) +"%Y-%m-%dT%H:%M:%S")
echo "$T1,Entrance Camera,Door Held Open,Unknown,30" >> "$CSV_FILE"

# Event 2: Server Room Camera - Access Denied - 2 hours ago
T2=$(date -d @$((NOW - 7200)) +"%Y-%m-%dT%H:%M:%S")
echo "$T2,Server Room Camera,Access Denied,J.Smith,5" >> "$CSV_FILE"

# Event 3: Parking Lot Camera - Barrier Force - 30 mins ago
T3=$(date -d @$((NOW - 1800)) +"%Y-%m-%dT%H:%M:%S")
echo "$T3,Parking Lot Camera,Barrier Forced,Vehicle-X,60" >> "$CSV_FILE"

# Event 4: Server Room Camera - Unauthorized Entry - 10 mins ago
T4=$(date -d @$((NOW - 600)) +"%Y-%m-%dT%H:%M:%S")
echo "$T4,Server Room Camera,Unauthorized Entry,Visitor_Badge_4,120" >> "$CSV_FILE"

chown ga:ga "$CSV_FILE"
chmod 644 "$CSV_FILE"

echo "CSV created at $CSV_FILE:"
cat "$CSV_FILE"

# Ensure Firefox is open to the Web Admin (helpful for manual verification if agent chooses)
ensure_firefox_running "https://localhost:7001/static/index.html#/view/cameras"
maximize_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="