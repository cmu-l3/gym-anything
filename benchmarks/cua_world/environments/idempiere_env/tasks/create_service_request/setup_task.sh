#!/bin/bash
set -e
echo "=== Setting up Create Service Request task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Get GardenWorld Client ID
CLIENT_ID=$(get_gardenworld_client_id)
if [ -z "$CLIENT_ID" ]; then
    echo "WARNING: Could not determine Client ID, defaulting to 11"
    CLIENT_ID=11
fi

# 3. Record initial request count
INITIAL_REQUEST_COUNT=$(idempiere_query "SELECT COUNT(*) FROM r_request WHERE ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")
echo "$INITIAL_REQUEST_COUNT" > /tmp/initial_request_count.txt
echo "Initial request count: $INITIAL_REQUEST_COUNT"

# 4. Verify Joe Block exists (Prerequisite)
JOE_BLOCK_ID=$(idempiere_query "SELECT c_bpartner_id FROM c_bpartner WHERE name='Joe Block' AND ad_client_id=$CLIENT_ID LIMIT 1" 2>/dev/null || echo "")
if [ -z "$JOE_BLOCK_ID" ]; then
    echo "WARNING: Business Partner 'Joe Block' not found. Creating placeholder..."
    # Fallback: We rely on the agent finding 'Joe Block' or failing. 
    # In standard demo data he exists.
fi
echo "$JOE_BLOCK_ID" > /tmp/joe_block_id.txt

# 5. Ensure Request Types exist
R_TYPE_COUNT=$(idempiere_query "SELECT COUNT(*) FROM r_requesttype WHERE ad_client_id IN (0, $CLIENT_ID) AND isactive='Y'" 2>/dev/null || echo "0")
if [ "$R_TYPE_COUNT" -eq "0" ]; then
    echo "Creating default Request Type..."
    idempiere_query "INSERT INTO r_requesttype (r_requesttype_id, ad_client_id, ad_org_id, isactive, created, createdby, updated, updatedby, name, isdefault) VALUES ((SELECT COALESCE(MAX(r_requesttype_id), 1000000)+1 FROM r_requesttype), $CLIENT_ID, 0, 'Y', NOW(), 100, NOW(), 100, 'General Inquiry', 'Y')" 2>/dev/null || true
fi

# 6. Ensure Firefox is running and navigate to dashboard
echo "--- Ensuring iDempiere is accessible ---"
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox https://localhost:8443/webui/ &"
    sleep 15
fi

# Navigate to dashboard
ensure_idempiere_open ""

# Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 3

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="