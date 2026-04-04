#!/bin/bash
# Setup script for create_case_folders task

echo "=== Setting up Create Case Folders Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure ArkCase is accessible
ensure_portforward
wait_for_arkcase

# 1. Create the specific complaint case via API
echo "Creating required complaint case..."
CASE_TITLE="Records Management Folder Setup - 2024-RM-0047"
CASE_DETAILS="This case requires a standardized folder structure for upcoming litigation document review."

# Use the API to create the case
# The response should contain the case ID
RESPONSE=$(arkcase_api POST "plugin/complaint" "{
    \"caseType\": \"GENERAL\",
    \"complaintTitle\": \"${CASE_TITLE}\",
    \"details\": \"${CASE_DETAILS}\",
    \"priority\": \"Medium\",
    \"status\": \"ACTIVE\"
}" 2>/dev/null || echo "")

# Extract Case ID from response
# ArkCase API usually returns JSON with "id" or "complaintId"
CASE_ID=$(echo "$RESPONSE" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    # Handle various response formats
    print(d.get('complaintId', d.get('id', d.get('caseId', ''))))
except Exception:
    print('')
" 2>/dev/null || echo "")

if [ -z "$CASE_ID" ]; then
    echo "ERROR: Failed to create case via API. Response: $RESPONSE"
    # Fallback: Try to find if it already exists (idempotency)
    # This might happen if task is restarted
    # For now, we'll proceed, but the agent might have to find it manually or fail
else
    echo "Created Case ID: $CASE_ID"
fi

# Save Case details for the export script/verifier
echo "$CASE_ID" > /tmp/task_case_id.txt
echo "$CASE_TITLE" > /tmp/task_case_title.txt

# 2. Prepare Firefox
# Kill any existing Firefox and clean lock files
pkill -9 -f firefox 2>/dev/null || true
sleep 2
find /home/ga -name ".parentlock" -delete 2>/dev/null || true
find /home/ga -name "parent.lock" -delete 2>/dev/null || true

# Launch Firefox
echo "Launching Firefox..."
# Use profile with SSL exceptions if available
SNAP_PROFILE=$(find /home/ga/snap/firefox -name "prefs.js" 2>/dev/null | head -1 | xargs dirname 2>/dev/null || echo "")
LOGIN_URL="https://localhost:9443/arkcase/login"

if [ -n "$SNAP_PROFILE" ]; then
    su - ga -c "DISPLAY=:1 firefox -profile '$SNAP_PROFILE' '$LOGIN_URL' &>/dev/null &" &
else
    su - ga -c "DISPLAY=:1 firefox '$LOGIN_URL' &>/dev/null &" &
fi

# Wait for browser
sleep 15
focus_firefox
maximize_firefox

# 3. Auto-login
echo "Logging in..."
# Login coordinates (1920x1080)
# Username: (994, 312), Password: (994, 368), Log In: (994, 438)
DISPLAY=:1 xdotool mousemove 994 312 click 1
sleep 0.5
DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'arkcase-admin@dev.arkcase.com'
sleep 0.3
DISPLAY=:1 xdotool mousemove 994 368 click 1
sleep 0.5
DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'ArkCase1234!'
sleep 0.3
DISPLAY=:1 xdotool mousemove 994 438 click 1
sleep 10

# Navigate to Home/Dashboard to start fresh
DISPLAY=:1 xdotool key ctrl+l
sleep 0.5
DISPLAY=:1 xdotool type --clearmodifiers 'https://localhost:9443/arkcase/home'
DISPLAY=:1 xdotool key Return
sleep 5

# Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Case Created: $CASE_TITLE (ID: $CASE_ID)"