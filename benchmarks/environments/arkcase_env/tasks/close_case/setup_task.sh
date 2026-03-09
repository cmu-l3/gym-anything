#!/bin/bash
# pre_task: Set up the close_case task
# Creates a pre-existing FOIA complaint that needs to be closed,
# then logs into ArkCase and navigates to the Complaints module

echo "=== Setting up close_case task ==="

source /workspace/scripts/task_utils.sh

ensure_portforward
wait_for_arkcase

# Create the pre-existing complaint via REST API
# Based on a real EPA FOIA request from public EPA FOIA logs
CASE_TITLE="FOIA Request - Climate Change Adaptation Plans - EPA FY2022"
CASE_DETAILS="Request for all agency climate change adaptation plans, internal memos, and \
correspondence related to EPA's FY2022 climate adaptation implementation. \
Requester: Center for Biological Diversity. Received: 2022-10-14. \
Request Number: EPA-HQ-2022-010472."

echo "Creating pre-existing FOIA complaint via API..."
RESPONSE=$(arkcase_api POST "plugin/complaint" "{
    \"caseType\": \"GENERAL\",
    \"complaintTitle\": \"${CASE_TITLE}\",
    \"details\": \"${CASE_DETAILS}\",
    \"priority\": \"Medium\",
    \"status\": \"ACTIVE\"
}" 2>/dev/null || echo "")

if echo "$RESPONSE" | grep -qi "error\|exception" || [ -z "$RESPONSE" ]; then
    echo "API call may have failed, case might need to be created manually"
    echo "API response: $RESPONSE"
else
    CASE_ID=$(echo "$RESPONSE" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('complaintId', d.get('id', '')))
except:
    print('')
" 2>/dev/null || echo "")
    echo "Pre-existing complaint created with ID: $CASE_ID"
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

# Navigate to Complaints module where the pre-created complaint appears
DISPLAY=:1 xdotool key ctrl+l
sleep 0.5
DISPLAY=:1 xdotool type --clearmodifiers 'https://localhost:9443/arkcase/#!/complaints'
DISPLAY=:1 xdotool key Return
sleep 6

focus_firefox
maximize_firefox
take_screenshot /tmp/task_start.png

echo "=== close_case task setup complete ==="
echo "Agent should: find 'FOIA Request - Climate Change Adaptation Plans - EPA FY2022', open it, change status to 'Closed', add disposition note, save"
