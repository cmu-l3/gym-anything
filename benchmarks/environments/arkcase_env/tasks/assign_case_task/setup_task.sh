#!/bin/bash
# pre_task: Set up the assign_case_task task
# Creates a pre-existing FOIA complaint, logs into ArkCase,
# and navigates to the Complaints module

echo "=== Setting up assign_case_task task ==="

source /workspace/scripts/task_utils.sh

ensure_portforward
wait_for_arkcase

# Create the pre-existing case via REST API
# Based on a real EPA Superfund FOIA request
CASE_TITLE="FOIA Request - Superfund Site Contamination Records - Chicago IL"
CASE_DETAILS="Request for all records related to contamination assessments, remediation plans, \
and community health studies at Superfund sites in Cook County, Illinois. \
Requester: Earthjustice Legal Defense Fund. \
Received: 2023-02-28. Request Number: EPA-HQ-SFUND-2023-000847."

echo "Creating pre-existing FOIA complaint via API..."
CASE_RESPONSE=$(arkcase_api POST "plugin/complaint" "{
    \"caseType\": \"GENERAL\",
    \"complaintTitle\": \"${CASE_TITLE}\",
    \"details\": \"${CASE_DETAILS}\",
    \"priority\": \"High\",
    \"status\": \"ACTIVE\"
}" 2>/dev/null || echo "")

CASE_ID=$(echo "$CASE_RESPONSE" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('complaintId', d.get('id', d.get('caseId', ''))))
except:
    print('')
" 2>/dev/null || echo "")

if [ -n "$CASE_ID" ]; then
    echo "Pre-existing complaint created with ID: $CASE_ID"
else
    echo "WARNING: Could not get case ID. Case may already exist."
fi

# Kill any existing Firefox and clean lock files
pkill -9 -f firefox 2>/dev/null || true
sleep 4
find /home/ga -name ".parentlock" -delete 2>/dev/null || true
find /home/ga -name "parent.lock" -delete 2>/dev/null || true

# Launch Firefox on ArkCase login page
# The Firefox snap profile already has the SSL exception stored
SNAP_PROFILE=$(find /home/ga/snap/firefox -name "prefs.js" 2>/dev/null | head -1 | xargs dirname 2>/dev/null || echo "")
if [ -n "$SNAP_PROFILE" ]; then
    su - ga -c "DISPLAY=:1 firefox -profile '$SNAP_PROFILE' 'https://localhost:9443/arkcase/login' &>/dev/null &" &
else
    su - ga -c "DISPLAY=:1 firefox 'https://localhost:9443/arkcase/login' &>/dev/null &" &
fi
sleep 20

focus_firefox
maximize_firefox
sleep 2

# Log in to ArkCase
# Login form coordinates in 1920x1080:
#   Username: (994, 312), Password: (994, 368), Log In button: (994, 438)
DISPLAY=:1 xdotool mousemove 994 312 click 1
sleep 0.5
DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'arkcase-admin@dev.arkcase.com'
sleep 0.3
DISPLAY=:1 xdotool mousemove 994 368 click 1
sleep 0.5
DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'ArkCase1234!'
sleep 0.3
DISPLAY=:1 xdotool mousemove 994 438 click 1
sleep 12

# Navigate to Complaints module where the pre-created case appears
DISPLAY=:1 xdotool key ctrl+l
sleep 0.5
DISPLAY=:1 xdotool type --clearmodifiers 'https://localhost:9443/arkcase/#!/complaints'
DISPLAY=:1 xdotool key Return
sleep 6

focus_firefox
maximize_firefox
take_screenshot /tmp/task_start.png

echo "=== assign_case_task setup complete ==="
echo "Agent should: find 'FOIA Request - Superfund Site Contamination Records - Chicago IL', open it, scroll to Tasks section, click + to add task 'Review and Redact Responsive Documents', assign to admin, save"
