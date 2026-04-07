#!/bin/bash
echo "=== Setting up design_workflow task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Clean up any previous attempts (Anti-Gaming / Idempotency)
# We deactivate any existing workflows with this specific name to ensure we test new creation
echo "--- Cleaning up previous workflows ---"
CLIENT_ID=$(get_gardenworld_client_id)
if [ -n "$CLIENT_ID" ]; then
    # Deactivate old workflows with this name to avoid confusion
    idempiere_query "UPDATE AD_Workflow SET IsActive='N', Name=Name||'_OLD_'||to_char(now(),'HH24MISS') WHERE Name='Project_Initiation_WF' AND AD_Client_ID=$CLIENT_ID" 2>/dev/null || true
fi

# 2. Record initial workflow count
INITIAL_WF_COUNT=$(idempiere_query "SELECT COUNT(*) FROM AD_Workflow WHERE AD_Client_ID=${CLIENT_ID:-11}" 2>/dev/null || echo "0")
echo "$INITIAL_WF_COUNT" > /tmp/initial_wf_count.txt
echo "Initial workflow count: $INITIAL_WF_COUNT"

# 3. Ensure Firefox is running and navigate to iDempiere
echo "--- Checking Firefox/iDempiere state ---"
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox https://localhost:8443/webui/ &"
    sleep 15
fi

# Navigate to Dashboard to ensure clean start
ensure_idempiere_open ""

# Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured."

echo "=== Task setup complete ==="