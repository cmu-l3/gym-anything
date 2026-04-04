#!/bin/bash
echo "=== Setting up Create Additional Field Task ==="
source /workspace/scripts/task_utils.sh

# 1. Ensure SDP is running (this handles the heavy lifting of waiting for install)
ensure_sdp_running

# 2. Record Task Start Time
date +%s > /tmp/task_start_time.txt

# 3. Check for pre-existing field (Clean State Check)
# We want to make sure the field doesn't already exist to avoid false positives
echo "Checking for existing field..."
EXISTING_FIELD=$(sdp_db_exec "SELECT column_alias FROM columndetails WHERE column_alias ILIKE '%Affected Network Segment%';")

if [ -n "$EXISTING_FIELD" ]; then
    echo "WARNING: Field 'Affected Network Segment' already exists!"
    # In a real scenario, we might try to delete it, but deleting metadata in SDP is risky without API.
    # We'll record this state to inform the verifier.
    echo "true" > /tmp/pre_existing_field.txt
else
    echo "false" > /tmp/pre_existing_field.txt
    echo "Clean state confirmed."
fi

# 4. Open Firefox to the Admin page or Home page
# The agent needs to navigate to Admin, so starting at Home is good.
echo "Launching Firefox..."
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Login.do"
sleep 5

# 5. Capture Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="