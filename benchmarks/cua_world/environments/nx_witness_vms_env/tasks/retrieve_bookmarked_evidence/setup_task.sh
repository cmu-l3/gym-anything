#!/bin/bash
set -e
echo "=== Setting up retrieve_bookmarked_evidence task ==="

source /workspace/scripts/task_utils.sh

# 1. Record Start Time
date +%s > /tmp/task_start_time.txt

# 2. Ensure Nx Server is up and we have a token
refresh_nx_token > /dev/null
TOKEN=$(get_nx_token)

if [ -z "$TOKEN" ]; then
    echo "ERROR: Failed to get Nx Witness auth token."
    exit 1
fi

# 3. Get a working camera
# We need a camera that is currently "recording". The testcamera in the env setup 
# should be running. We'll pick the first available camera.
CAMERA_ID=$(get_first_camera_id)

if [ -z "$CAMERA_ID" ]; then
    echo "ERROR: No cameras found. Attempting to restart testcamera..."
    # Attempt restart logic (simplified from env setup)
    TESTCAMERA=$(find /opt -name testcamera -type f | head -1)
    SERVER_IP=$(ip route get 1.1.1.1 | awk '{print $7; exit}')
    nohup "$TESTCAMERA" --local-interface="${SERVER_IP}" "channels=1" > /dev/null 2>&1 &
    sleep 10
    CAMERA_ID=$(get_first_camera_id)
fi

if [ -z "$CAMERA_ID" ]; then
    echo "CRITICAL: Could not find or start a camera."
    exit 1
fi

echo "Target Camera ID: $CAMERA_ID"
echo "$CAMERA_ID" > /tmp/target_camera_id.txt

# 4. Ensure Recording is Enabled
# The env setup enables recording, but we force it here to be sure
# We also set a buffer size to Ensure we have history
enable_recording_for_camera "$CAMERA_ID" "24" > /dev/null

# 5. Generate History and Bookmarks
echo "Generating recording history..."

# We need to wait a bit so there is actual footage *before* the bookmark
# sleep 30s to create pre-bookmark footage
sleep 30

# Calculate timestamps (in milliseconds)
# We want the bookmark to be slightly in the past so the "post-bookmark" buffer exists too.
# Let's define the bookmark event as happening "now" and waiting for the post-buffer.
# Actually, to be safe, we place the bookmark at NOW, and then wait for (Duration + Buffer + Margin).

NOW_MS=$(date +%s%3N)
BOOKMARK_START_MS=$NOW_MS
BOOKMARK_DURATION_MS=10000 # 10 seconds

# Create Distractor Bookmarks (historical)
nx_api_post "/rest/v1/devices/$CAMERA_ID/bookmarks" \
    "{\"name\":\"System Check\",\"startTimeMs\":$((NOW_MS - 60000)),\"durationMs\":5000,\"description\":\"Routine maintenance\"}" > /dev/null

nx_api_post "/rest/v1/devices/$CAMERA_ID/bookmarks" \
    "{\"name\":\"Door Sensor Test\",\"startTimeMs\":$((NOW_MS - 45000)),\"durationMs\":2000,\"description\":\"Sensor active\"}" > /dev/null

# Create Target Bookmark
echo "Creating target bookmark 'Staff Altercation'..."
nx_api_post "/rest/v1/devices/$CAMERA_ID/bookmarks" \
    "{\"name\":\"Staff Altercation\",\"startTimeMs\":$BOOKMARK_START_MS,\"durationMs\":$BOOKMARK_DURATION_MS,\"description\":\"Incident reported by HR\"}"

# Save bookmark details for verification
echo "$BOOKMARK_DURATION_MS" > /tmp/target_bookmark_duration_ms.txt
echo "$BOOKMARK_START_MS" > /tmp/target_bookmark_start_ms.txt

# 6. Wait for the event + post-buffer to be recorded
# We need 10s (duration) + 10s (buffer) + 10s (safety margin)
echo "Waiting for event recording to complete..."
sleep 35

# 7. Prepare Browser
# Open Firefox to the Bookmarks or Camera view to help the agent start
ensure_firefox_running "https://localhost:7001/static/index.html#/view/$CAMERA_ID"
maximize_firefox

# 8. Clean up old exports if any
rm -f /home/ga/Documents/evidence_export.mkv

# 9. Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="