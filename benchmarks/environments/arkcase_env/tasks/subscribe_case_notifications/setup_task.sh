#!/bin/bash
# pre_task: Set up the subscribe_case_notifications task
# 1. Create a specific complaint case via API
# 2. Ensure admin is NOT already subscribed
# 3. Launch Firefox on login page

echo "=== Setting up subscribe_case_notifications task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Ensure ArkCase is accessible
ensure_portforward
wait_for_arkcase

# Define Case Details
CASE_TITLE="Improper Records Retention Complaint"
CASE_DETAILS="Citizen reports that the Office of Administrative Services has failed to retain correspondence records from fiscal years 2021-2023 in violation of the Federal Records Act. The citizen requests an investigation into records retention compliance."

# 1. Create the Complaint Case via API
echo "Creating target complaint case..."
# Note: Using complaintTitle (ArkCase specific field)
PAYLOAD=$(cat <<EOF
{
    "caseType": "GENERAL",
    "complaintTitle": "$CASE_TITLE",
    "details": "$CASE_DETAILS",
    "priority": "High",
    "status": "ACTIVE"
}
EOF
)

RESPONSE=$(arkcase_api POST "plugin/complaint" "$PAYLOAD" 2>/dev/null)

# Extract Case ID from response
# Response format example: {"complaintId":"20250101_000001", ...} or {"id":...}
CASE_ID=$(echo "$RESPONSE" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    # Try common ID fields
    print(d.get('complaintId', d.get('id', d.get('caseId', ''))))
except Exception as e:
    print('')
" 2>/dev/null)

if [ -z "$CASE_ID" ]; then
    echo "ERROR: Failed to create case via API. Response: $RESPONSE"
    # Fallback: Just proceed, maybe case exists? But verifier needs ID.
    # We will try to search for it later in export if ID is missing here.
    echo "Using fallback ID search strategy in export."
else
    echo "Target Case Created: $CASE_ID"
    echo "$CASE_ID" > /tmp/target_case_id.txt
fi

# 2. Ensure Admin is NOT subscribed (Clean State)
# We attempt to unsubscribe just in case
if [ -n "$CASE_ID" ]; then
    echo "Ensuring no existing subscription..."
    # API endpoint to remove subscription: DELETE /api/v1/service/subscription/{user}/objType/{type}/objId/{id}
    # Note: If not subscribed, this might 404, which is fine.
    arkcase_api DELETE "service/subscription/${ARKCASE_ADMIN}/objType/COMPLAINT/objId/${CASE_ID}" 2>/dev/null || true
fi

# 3. Launch Firefox
echo "Launching Firefox..."
# Clean up locks
pkill -9 -f firefox 2>/dev/null || true
rm -f /home/ga/.mozilla/firefox/*.default*/lock 2>/dev/null || true
rm -f /home/ga/.mozilla/firefox/*.default*/.parentlock 2>/dev/null || true

# Find profile with SSL exception
SNAP_PROFILE=$(find /home/ga/snap/firefox -name "prefs.js" 2>/dev/null | head -1 | xargs dirname 2>/dev/null || echo "")

LOGIN_URL="https://localhost:9443/arkcase/login"
if [ -n "$SNAP_PROFILE" ]; then
    su - ga -c "DISPLAY=:1 firefox -profile '$SNAP_PROFILE' '$LOGIN_URL' &>/dev/null &" &
else
    su - ga -c "DISPLAY=:1 firefox '$LOGIN_URL' &>/dev/null &" &
fi

# Wait for browser
sleep 15
maximize_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="