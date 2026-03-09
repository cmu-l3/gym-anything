#!/bin/bash
# Setup script for delete_case_record task
# 1. Ensures ArkCase is running
# 2. Creates the target case to be deleted
# 3. Creates a control case that must NOT be deleted
# 4. Logs in and positions the browser

echo "=== Setting up delete_case_record task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure ArkCase is accessible
ensure_portforward
wait_for_arkcase

# 2. Create the TARGET case (to be deleted)
echo "Creating target case: TEST-CASE-REMOVE-ME..."
TARGET_PAYLOAD=$(cat <<EOF
{
    "caseType": "GENERAL",
    "complaintTitle": "TEST-CASE-REMOVE-ME",
    "details": "This record is a duplicate created by training staff. Please remove.",
    "priority": "Low",
    "status": "NEW"
}
EOF
)

# Use existing arkcase_api function (POST /api/v1/plugin/complaint)
TARGET_RESPONSE=$(arkcase_api POST "plugin/complaint" "$TARGET_PAYLOAD")
echo "Target Response: $TARGET_RESPONSE"

# Extract ID
TARGET_ID=$(echo "$TARGET_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('complaintId', ''))" 2>/dev/null)

if [ -z "$TARGET_ID" ]; then
    echo "ERROR: Failed to create target case!"
    # Fallback/Retry logic could go here, but for now we exit or warn
    # Attempt to continue, maybe it already exists?
fi
echo "Target Case ID: $TARGET_ID" > /tmp/target_case_id.txt

# 3. Create the CONTROL case (to ensure safety)
echo "Creating control case: IMPORTANT-active-case-001..."
CONTROL_PAYLOAD=$(cat <<EOF
{
    "caseType": "GENERAL",
    "complaintTitle": "IMPORTANT-active-case-001",
    "details": "Do not delete this case. It is for testing collateral damage.",
    "priority": "High",
    "status": "ACTIVE"
}
EOF
)
CONTROL_RESPONSE=$(arkcase_api POST "plugin/complaint" "$CONTROL_PAYLOAD")
CONTROL_ID=$(echo "$CONTROL_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('complaintId', ''))" 2>/dev/null)
echo "Control Case ID: $CONTROL_ID" > /tmp/control_case_id.txt

# Record Total Initial Count (approximate)
# We can search for all complaints to get a count, but just storing IDs is sufficient for this task.

# 4. Browser Setup
# Kill any existing Firefox and clean lock files
pkill -9 -f firefox 2>/dev/null || true
sleep 2
find /home/ga -name ".parentlock" -delete 2>/dev/null || true
find /home/ga -name "parent.lock" -delete 2>/dev/null || true

# Launch Firefox
echo "Launching Firefox..."
SNAP_PROFILE=$(find /home/ga/snap/firefox -name "prefs.js" 2>/dev/null | head -1 | xargs dirname 2>/dev/null || echo "")
if [ -n "$SNAP_PROFILE" ]; then
    su - ga -c "DISPLAY=:1 firefox -profile '$SNAP_PROFILE' 'https://localhost:9443/arkcase/login' &>/dev/null &" &
else
    su - ga -c "DISPLAY=:1 firefox 'https://localhost:9443/arkcase/login' &>/dev/null &" &
fi
sleep 20

# 5. Auto-login and navigate to Complaints list
auto_login_arkcase "https://localhost:9443/arkcase/#!/complaints"

# 6. Final Prep
take_screenshot /tmp/task_initial.png
date +%s > /tmp/task_start_time.txt

echo "=== Setup complete ==="
echo "Target Case ID: $TARGET_ID (To delete)"
echo "Control Case ID: $CONTROL_ID (To keep)"