#!/bin/bash
echo "=== Setting up add_case_costs task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p /home/ga/Documents

# Ensure ArkCase is accessible
ensure_portforward
wait_for_arkcase

# 1. Create the FOIA Case via API
echo "Creating FOIA case..."
CASE_TITLE="FOIA-2024-00847 - Public Records Request for Environmental Inspection Reports"
CASE_DETAILS="Request for all environmental inspection reports for the facility at 123 Industrial Way, Boston MA, dated between 2020 and 2024."

# Construct JSON payload for complaint creation
# Note: ArkCase API often returns the created object
RESPONSE=$(arkcase_api POST "plugin/complaint" "{
    \"caseType\": \"GENERAL\",
    \"complaintTitle\": \"${CASE_TITLE}\",
    \"details\": \"${CASE_DETAILS}\",
    \"priority\": \"Medium\",
    \"status\": \"ACTIVE\"
}" 2>/dev/null)

# Extract Case ID
# Python script to parse JSON response safely
CASE_ID=$(echo "$RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    # ID might be 'complaintId', 'id', or 'caseId' depending on version
    print(data.get('complaintId') or data.get('id') or data.get('caseId') or '')
except Exception:
    print('')
")

if [ -z "$CASE_ID" ]; then
    echo "ERROR: Failed to create case. API Response: $RESPONSE"
    # Fallback: Try to find if it already exists
    # (In a real scenario, we might fail here, but we'll try to proceed for robustness)
    exit 1
else
    echo "Created Case ID: $CASE_ID"
    echo "$CASE_ID" > /tmp/arkcase_case_id.txt
fi

# 2. Record initial cost state (Should be 0)
# We query the cost/expenses endpoint for this case
# Assuming endpoint structure: /api/v1/case/{id}/expenses or similar
# For generic checking, we'll assume 0 since it's a new case.
echo "0" > /tmp/initial_cost_count.txt

# 3. Setup Firefox
# Kill any existing Firefox
pkill -9 -f firefox 2>/dev/null || true
sleep 2
find /home/ga -name ".parentlock" -delete 2>/dev/null || true
find /home/ga -name "parent.lock" -delete 2>/dev/null || true

# Construct URL for the specific case
# ArkCase standard URL pattern: /arkcase/#!/complaints/{id} or /arkcase/#!/case/{id}
# We'll default to the complaints list or specific case if possible. 
# Navigating to the specific case ID is best.
CASE_URL="https://localhost:9443/arkcase/#!/complaint/${CASE_ID}"

# Launch Firefox
echo "Launching Firefox to $CASE_URL..."
SNAP_PROFILE=$(find /home/ga/snap/firefox -name "prefs.js" 2>/dev/null | head -1 | xargs dirname 2>/dev/null || echo "")

if [ -n "$SNAP_PROFILE" ]; then
    # Use existing profile (has SSL exceptions)
    su - ga -c "DISPLAY=:1 firefox -profile '$SNAP_PROFILE' 'https://localhost:9443/arkcase/login' &"
else
    su - ga -c "DISPLAY=:1 firefox 'https://localhost:9443/arkcase/login' &"
fi

# Wait for Firefox window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Firefox"; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done

# Focus and maximize
focus_firefox
maximize_firefox
sleep 5

# Auto-login and navigate
# Using the helper from task_utils.sh which handles the login coordinate clicks
auto_login_arkcase "$CASE_URL"

# 4. Final Setup Checks
# Take initial screenshot
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="