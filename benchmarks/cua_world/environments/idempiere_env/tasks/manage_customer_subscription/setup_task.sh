#!/bin/bash
set -e
echo "=== Setting up manage_customer_subscription task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 1. Clean up any pre-existing data (in case of re-runs) to ensure clean state
echo "--- Cleaning up potential pre-existing data ---"
CLIENT_ID=$(get_gardenworld_client_id)
CLIENT_ID=${CLIENT_ID:-11}

# Deactivate/Delete Subscription
idempiere_query "UPDATE c_subscription SET isactive='N', name=name||'_OLD' WHERE name='C&W HQ Maintenance 2025' AND ad_client_id=$CLIENT_ID" 2>/dev/null || true

# Deactivate/Delete Subscription Type
idempiere_query "UPDATE c_subscriptiontype SET isactive='N', name=name||'_OLD' WHERE name='Monthly Care Plan' AND ad_client_id=$CLIENT_ID" 2>/dev/null || true

# Deactivate/Delete Product
idempiere_query "UPDATE m_product SET isactive='N', value=value||'_OLD' WHERE value='SVC-GARDEN-001' AND ad_client_id=$CLIENT_ID" 2>/dev/null || true

echo "  Cleanup complete"

# 2. Record initial counts
INITIAL_PROD_COUNT=$(get_product_count)
INITIAL_SUB_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_subscription WHERE ad_client_id=$CLIENT_ID AND isactive='Y'" 2>/dev/null || echo "0")
echo "Initial Product Count: $INITIAL_PROD_COUNT"
echo "Initial Subscription Count: $INITIAL_SUB_COUNT"
echo "$INITIAL_PROD_COUNT" > /tmp/initial_prod_count.txt
echo "$INITIAL_SUB_COUNT" > /tmp/initial_sub_count.txt

# 3. Ensure Firefox is running and navigate to iDempiere dashboard
echo "--- Navigating to iDempiere ---"
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "  Firefox not running, launching..."
    su - ga -c "DISPLAY=:1 firefox https://localhost:8443/webui/ &"
    sleep 15
fi

# Navigate to iDempiere dashboard
ensure_idempiere_open ""

# Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 3

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png
echo "  Initial screenshot saved to /tmp/task_initial.png"

echo "=== Task setup complete ==="