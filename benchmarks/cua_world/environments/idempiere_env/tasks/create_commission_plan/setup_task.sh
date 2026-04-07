#!/bin/bash
echo "=== Setting up create_commission_plan task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 1. Clean up previous runs (Idempotency)
echo "--- Cleaning up previous test data ---"
CLIENT_ID=$(get_gardenworld_client_id)
if [ -n "$CLIENT_ID" ]; then
    # Delete commission lines first (foreign key constraint)
    idempiere_query "DELETE FROM c_commissionline WHERE c_commission_id IN (SELECT c_commission_id FROM c_commission WHERE value='COMM-Q3-2024' AND ad_client_id=$CLIENT_ID)" 2>/dev/null || true
    # Delete commission header
    idempiere_query "DELETE FROM c_commission WHERE value='COMM-Q3-2024' AND ad_client_id=$CLIENT_ID" 2>/dev/null || true
    echo "  Cleanup complete for client $CLIENT_ID"
else
    echo "  WARNING: Could not determine Client ID, skipping cleanup"
fi

# 2. Record initial count of commissions
INITIAL_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_commission WHERE ad_client_id=${CLIENT_ID:-11}" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_commission_count.txt

# 3. Ensure Firefox is running and logged in
echo "--- Ensuring iDempiere is ready ---"
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "  Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox https://localhost:8443/webui/ &"
    sleep 15
fi

# Navigate to dashboard to ensure clean state (handles ZK leave-page dialog)
ensure_idempiere_open ""

# Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="