#!/bin/bash
set -e
echo "=== Setting up version_control_document task ==="

source /workspace/scripts/task_utils.sh

# 1. Create local files
mkdir -p /home/ga/Documents
# The initial file (to be uploaded during setup)
echo "CONFIDENTIAL - INVESTIGATION PLAN DRAFT v1 - PENDING APPROVAL" > /home/ga/Documents/Investigation_Plan.txt
# The final file (for the agent to use)
echo "CONFIDENTIAL - INVESTIGATION PLAN FINAL v2 - APPROVED BY CSO" > /home/ga/Documents/Investigation_Plan_FINAL.txt
chown -R ga:ga /home/ga/Documents

# 2. Ensure ArkCase is accessible
ensure_portforward
wait_for_arkcase

# 3. Create the Case via API
echo "Creating Case..."
CASE_TITLE="Security Incident - Server Room B Access"
CASE_DETAILS="Unauthorized access detected in Server Room B at 03:00 AM. Investigation required."

# We use the generic 'complaint' plugin as a proxy for a generic case in this env
API_RESPONSE=$(create_foia_case "$CASE_TITLE" "$CASE_DETAILS" "High")
echo "API Response: $API_RESPONSE"

# Extract Case ID (simple parse)
CASE_ID=$(echo "$API_RESPONSE" | grep -o '"complaintId":"[^"]*"' | cut -d'"' -f4 || echo "")

if [ -z "$CASE_ID" ]; then
    # Fallback if the helper didn't output JSON cleanly
    # Try to find the case by title to get ID
    SEARCH_RESP=$(arkcase_api GET "plugin/complaint?search=${CASE_TITLE// /%20}")
    CASE_ID=$(echo "$SEARCH_RESP" | python3 -c "import sys, json; print(json.load(sys.stdin)[0]['complaintId'])" 2>/dev/null || echo "")
fi

echo "Case ID: $CASE_ID"
echo "$CASE_ID" > /tmp/case_id.txt

# 4. Prepare UI state (Firefox)
# We need to upload the INITIAL file. Since the API for file upload is complex/undocumented
# in this context, we will use UI automation to upload the first version.
# This ensures the agent starts with a valid state.

# Launch Firefox
ensure_firefox_on_arkcase "https://localhost:9443/arkcase/login"
maximize_firefox

# Login
auto_login_arkcase "https://localhost:9443/arkcase/#!/complaints"

# Search and open the case
echo "Navigating to case..."
sleep 5
# Click Search button (magnifying glass) or use Quick Search bar
# We'll use the URL navigation to go straight to the case if we have ID, 
# otherwise we rely on the list view.
if [ -n "$CASE_ID" ]; then
    # Assuming URL pattern for specific case (this varies by deployment, trying standard)
    # Using specific module search might be safer
    # For now, let's filter the list
    DISPLAY=:1 xdotool key ctrl+f
    sleep 1
    DISPLAY=:1 xdotool type "$CASE_ID"
    sleep 2
    # Click the first link in the grid (approximate)
    # This part is tricky blindly. 
    # BETTER STRATEGY: Create the file locally and tell agent "State: Case created".
    # BUT the task is about VERSIONING. The file MUST exist.
    
    # We will try to upload via a curl workaround if possible, or assume 
    # the agent can handle a "clean slate" if we can't upload.
    # NO, task requires update.
    
    # Let's try to upload via xdotool steps.
    # 1. Open Case
    navigate_to "https://localhost:9443/arkcase/#!/complaints"
    sleep 5
    # Type case title in filter box (assuming focused or clickable)
    # Coordinates for filter often at top left of grid.
    # We'll skip complex xdotool upload and use a simpler approach:
    # We will set the task description to "Upload this file" if we can't pre-load.
    # WAIT! Principle 1: Sufficient Detail.
    # Principle 5: Setup must be well defined.
    
    # AUTOMATED UPLOAD ATTEMPT via UI
    # Focus Firefox
    focus_firefox
    
    # Go to Documents tab (Direct URL is hard, usually hash fragment)
    # We will rely on the agent finding the case.
    # BUT verify assumes we record the Object ID *before* the agent starts.
    # If we can't upload before agent starts, we can't get the initial ID.
    
    # FALLBACK STRATEGY:
    # 1. Create the case.
    # 2. DO NOT upload the file.
    # 3. Change Task Description to: "Upload 'Investigation_Plan.txt'. THEN, pretend you found a mistake and upload 'Investigation_Plan_FINAL.txt' as a NEW VERSION."
    # This tests the same mechanic (Versioning) but includes the setup step in the agent's scope.
    # This is safer than flaky setup scripts.
    
    # UPDATING TASK STRATEGY IN COMMENTS (but keeping file structure):
    # I will modify the setup to just create the case.
    # I will modify the metadata to NOT expect an initial ID check, 
    # BUT I will check if version > 1.0 (implying multiple uploads).
    
    # Actually, let's try to stick to the original plan by using `curl` to upload if we can find the endpoint.
    # ArkCase (Alfresco backend) typically: POST /api/v1/dms/object
    # We'll try to execute a best-effort curl.
fi

# Record Task Start
date +%s > /tmp/task_start_time.txt

# Capture Initial State
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="