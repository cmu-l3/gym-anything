#!/bin/bash
# pre_task: Set up the search_and_update_case_priority task
# Creates background cases + target case, logs in, lands on dashboard

set -e
echo "=== Setting up search_and_update_case_priority task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

ensure_portforward
wait_for_arkcase

# 1. Create Background Cases (Noise)
echo "Creating background cases..."
# Case 1 (Medium)
arkcase_api POST "plugin/complaint" '{
    "caseType": "GENERAL",
    "complaintTitle": "Water Quality Testing Results - Municipal Report",
    "details": "Request for water quality lab results from Q1-Q3 2024.",
    "priority": "Medium",
    "status": "ACTIVE"
}' > /dev/null

# Case 3 (High)
arkcase_api POST "plugin/complaint" '{
    "caseType": "GENERAL",
    "complaintTitle": "Employee Workplace Safety Incident Review",
    "details": "Internal review of workplace incident report under OSHA section 11(c).",
    "priority": "High",
    "status": "ACTIVE"
}' > /dev/null

# Case 4 (Medium)
arkcase_api POST "plugin/complaint" '{
    "caseType": "GENERAL",
    "complaintTitle": "Annual Budget Disclosure Request - FY2024",
    "details": "Public request for itemized departmental budget allocations.",
    "priority": "Medium",
    "status": "ACTIVE"
}' > /dev/null

# Case 5 (Low)
arkcase_api POST "plugin/complaint" '{
    "caseType": "GENERAL",
    "complaintTitle": "Environmental Impact Assessment - Highway Project",
    "details": "EIA documents for proposed Interstate 94 expansion.",
    "priority": "Low",
    "status": "ACTIVE"
}' > /dev/null

# 2. Create Target Case
echo "Creating TARGET case..."
TARGET_TITLE="Delayed Public Records Response - EPA Region 5"
TARGET_RESPONSE=$(arkcase_api POST "plugin/complaint" "{
    \"caseType\": \"GENERAL\",
    \"complaintTitle\": \"${TARGET_TITLE}\",
    \"details\": \"FOIA request regarding EPA enforcement actions in Region 5, response overdue.\",
    \"priority\": \"Low\",
    \"status\": \"ACTIVE\"
}" 2>/dev/null)

# Extract Case ID (using python for reliability)
TARGET_ID=$(echo "$TARGET_RESPONSE" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    # ID field can vary based on API version, checking common ones
    print(d.get('complaintId', d.get('id', '')))
except:
    print('')
")

if [ -z "$TARGET_ID" ]; then
    echo "ERROR: Failed to create target case or parse ID."
    echo "Response: $TARGET_RESPONSE"
    # Fallback/Exit? We'll continue but export will fail.
else
    echo "Target Case Created: ID $TARGET_ID"
    # Save ID for verification (Agent does not see this)
    echo "$TARGET_ID" > /tmp/target_case_id.txt
    echo "Low" > /tmp/initial_priority.txt
fi

# 3. Setup Browser
echo "Setting up Firefox..."
# Kill any existing Firefox and clean lock files
pkill -9 -f firefox 2>/dev/null || true
sleep 2
find /home/ga -name ".parentlock" -delete 2>/dev/null || true
find /home/ga -name "parent.lock" -delete 2>/dev/null || true

# Launch Firefox (headless logic or background)
SNAP_PROFILE=$(find /home/ga/snap/firefox -name "prefs.js" 2>/dev/null | head -1 | xargs dirname 2>/dev/null || echo "")
if [ -n "$SNAP_PROFILE" ]; then
    su - ga -c "DISPLAY=:1 firefox -profile '$SNAP_PROFILE' 'https://localhost:9443/arkcase/login' &>/dev/null &" &
else
    su - ga -c "DISPLAY=:1 firefox 'https://localhost:9443/arkcase/login' &>/dev/null &" &
fi
sleep 20

# 4. Automate Login
echo "Logging in..."
focus_firefox
maximize_firefox
sleep 2

# Login coordinates (1920x1080)
# Username
DISPLAY=:1 xdotool mousemove 994 312 click 1
sleep 0.5
DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'arkcase-admin@dev.arkcase.com'
sleep 0.5
# Password
DISPLAY=:1 xdotool mousemove 994 368 click 1
sleep 0.5
DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'ArkCase1234!'
sleep 0.5
# Click Login
DISPLAY=:1 xdotool mousemove 994 438 click 1
sleep 15

# Ensure we are on Dashboard
navigate_to "https://localhost:9443/arkcase/#!/home"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="