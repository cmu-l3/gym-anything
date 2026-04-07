#!/bin/bash
set -e
echo "=== Setting up Export Incident Evidence Task ==="

source /workspace/scripts/task_utils.sh

# Directory setup
mkdir -p /home/ga/evidence
chown ga:ga /home/ga/evidence

# 1. Ensure "Parking Lot Camera" is recording
# -------------------------------------------
echo "Configuring recording for Parking Lot Camera..."
refresh_nx_token > /dev/null 2>&1 || true
CAM_ID=$(get_camera_id_by_name "Parking Lot Camera")

if [ -z "$CAM_ID" ]; then
    echo "ERROR: Parking Lot Camera not found. Using first available."
    CAM_ID=$(get_first_camera_id)
fi

# Enable high-fps recording to ensure we have frames
enable_recording_for_camera "$CAM_ID" "25" > /dev/null 2>&1 || true
echo "Recording enabled for camera $CAM_ID"

# Wait a bit to ensure some footage exists
echo "Waiting for footage to accumulate (10s)..."
sleep 10

# 2. Generate Incident Ticket
# ---------------------------
# Calculate timestamps (in milliseconds)
# Scenario: Incident happened 1 minute ago, lasted 30 seconds
CURRENT_TIME_MS=$(date +%s%3N)
# End time: 30 seconds ago
END_TIME_MS=$((CURRENT_TIME_MS - 30000))
# Start time: 60 seconds ago (30s duration)
START_TIME_MS=$((CURRENT_TIME_MS - 60000))
CASE_ID="4492"

TICKET_FILE="/home/ga/incident_ticket.json"
cat > "$TICKET_FILE" << EOF
{
  "case_id": "$CASE_ID",
  "camera_name": "Parking Lot Camera",
  "camera_id": "$CAM_ID",
  "start_time_ms": $START_TIME_MS,
  "end_time_ms": $END_TIME_MS,
  "notes": "Theft reported in Sector B. Export raw footage for police evidence."
}
EOF
chown ga:ga "$TICKET_FILE"

echo "Generated ticket: $TICKET_FILE"
cat "$TICKET_FILE"

# Save expected values for export_result script
echo "$CASE_ID" > /tmp/expected_case_id.txt
echo "$START_TIME_MS" > /tmp/expected_start_ms.txt
echo "$END_TIME_MS" > /tmp/expected_end_ms.txt

# 3. Open Firefox to Web Admin
# ----------------------------
echo "Launching Firefox..."
ensure_firefox_running "https://localhost:7001/static/index.html#/view/${CAM_ID}"
sleep 5
maximize_firefox
dismiss_ssl_warning

# 4. Record Initial State
# -----------------------
date +%s > /tmp/task_start_time.txt
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="