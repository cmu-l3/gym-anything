#!/bin/bash
echo "=== Setting up create_business_partner task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Remove any pre-existing test business partner with the same search key
echo "--- Cleaning up pre-existing test data ---"
CLIENT_ID=$(get_gardenworld_client_id)
if [ -n "$CLIENT_ID" ]; then
    idempiere_query "UPDATE c_bpartner SET isactive='N' WHERE value='RIVERSIDE01' AND ad_client_id=$CLIENT_ID" 2>/dev/null || true
    echo "  Cleanup complete (client_id=$CLIENT_ID)"
else
    echo "  WARNING: Could not get GardenWorld client ID"
fi

# 2. Record initial business partner count for verification baseline
INITIAL_BP_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_bpartner WHERE ad_client_id=${CLIENT_ID:-11} AND isactive='Y'" 2>/dev/null || echo "0")
echo "Initial active business partner count: $INITIAL_BP_COUNT"
rm -f /tmp/initial_bp_count.txt 2>/dev/null || true
echo "$INITIAL_BP_COUNT" > /tmp/initial_bp_count.txt
chmod 666 /tmp/initial_bp_count.txt 2>/dev/null || true

# 3. Ensure Firefox is running and navigate to iDempiere dashboard
echo "--- Navigating to iDempiere dashboard ---"
# Check if Firefox is running
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "  Firefox not running, launching..."
    su - ga -c "DISPLAY=:1 firefox https://localhost:8443/webui/ &"
    sleep 15
fi

# Navigate to iDempiere dashboard (handles ZK leave-page dialog automatically)
ensure_idempiere_open ""

# Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 3

# 4. Take initial screenshot for evidence
take_screenshot /tmp/create_business_partner_initial.png
echo "  Initial screenshot saved to /tmp/create_business_partner_initial.png"

echo "=== create_business_partner task setup complete ==="
echo "Task: Create Business Partner 'Riverside Landscaping Co.' (Search Key: RIVERSIDE01)"
echo "Navigation hint: Menu > Partner Relations > Business Partner > New Record"
