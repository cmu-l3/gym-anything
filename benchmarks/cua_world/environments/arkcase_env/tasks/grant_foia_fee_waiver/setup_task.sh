#!/bin/bash
# pre_task: Set up the grant_foia_fee_waiver task
# Creates the specific FOIA case and logs the user in

echo "=== Setting up grant_foia_fee_waiver task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure ArkCase is accessible
ensure_portforward
wait_for_arkcase

# 2. Create the specific FOIA case via API
echo "Creating FOIA case..."
CASE_TITLE="FOIA Request - Environmental Impact Data - 2026"
CASE_DETAILS="Request for environmental impact assessments regarding the new coastal energy project. Requester: Elena Rossi (Journalist)."

# Create case using the helper function or direct API call
# We capture the full response to extract the generated Case Number
RESPONSE=$(arkcase_api POST "plugin/complaint" "{
    \"caseType\": \"GENERAL\",
    \"complaintTitle\": \"${CASE_TITLE}\",
    \"details\": \"${CASE_DETAILS}\",
    \"priority\": \"Medium\",
    \"status\": \"ACTIVE\"
}" 2>/dev/null || echo "")

# Extract Case ID and Number
# Note: ArkCase returns different ID formats depending on version, we try to grab the complaintNumber
CASE_NUMBER=$(echo "$RESPONSE" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('complaintNumber', d.get('caseNumber', 'UNKNOWN')))
except:
    print('UNKNOWN')
" 2>/dev/null)

CASE_GUID=$(echo "$RESPONSE" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('complaintId', d.get('id', '')))
except:
    print('')
" 2>/dev/null)

echo "Created Case: $CASE_NUMBER (GUID: $CASE_GUID)"

# 3. Create a hint file for the agent
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/case_info.txt <<EOF
TASK INFORMATION
================
Case Title: $CASE_TITLE
Case Number: $CASE_NUMBER
Requester: Elena Rossi

Action Required:
1. Locate this case in ArkCase.
2. Grant a Fee Waiver.
3. Add Justification: "Requester is a member of the news media and disclosure is in the public interest."
EOF
chmod 644 /home/ga/Documents/case_info.txt

# Save Case GUID for the exporter/verifier to use later
echo "$CASE_GUID" > /tmp/task_case_guid.txt

# 4. Launch Firefox and Login
# Kill any existing Firefox and clean lock files
pkill -9 -f firefox 2>/dev/null || true
sleep 2
find /home/ga -name ".parentlock" -delete 2>/dev/null || true
find /home/ga -name "parent.lock" -delete 2>/dev/null || true

# Launch Firefox
SNAP_PROFILE=$(find /home/ga/snap/firefox -name "prefs.js" 2>/dev/null | head -1 | xargs dirname 2>/dev/null || echo "")
URL="https://localhost:9443/arkcase/login"

if [ -n "$SNAP_PROFILE" ]; then
    su - ga -c "DISPLAY=:1 firefox -profile '$SNAP_PROFILE' '$URL' &>/dev/null &" &
else
    su - ga -c "DISPLAY=:1 firefox '$URL' &>/dev/null &" &
fi
sleep 15

# Automate Login
focus_firefox
maximize_firefox
sleep 2

# Login coordinates (1920x1080)
# User: 994, 312 | Pass: 994, 368 | Button: 994, 438
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

# Navigate to Complaints module
DISPLAY=:1 xdotool key ctrl+l
sleep 0.5
DISPLAY=:1 xdotool type --clearmodifiers 'https://localhost:9443/arkcase/#!/complaints'
DISPLAY=:1 xdotool key Return
sleep 5

# 5. Final Setup Steps
date +%s > /tmp/task_start_time
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="