#!/bin/bash
set -e
echo "=== Setting up configure_payment_term task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# 2. Clean up any pre-existing payment term with the same search key
# We check both the specific client (GardenWorld) and System (*) client just in case
echo "--- Cleaning up pre-existing test data ---"
CLIENT_ID=$(get_gardenworld_client_id)
if [ -n "$CLIENT_ID" ]; then
    idempiere_query "DELETE FROM c_paymentterm WHERE value='2-10-Net-45'" 2>/dev/null || true
    echo "  Cleanup complete for search key '2-10-Net-45'"
else
    echo "  WARNING: Could not get GardenWorld client ID, attempting generic cleanup"
    idempiere_query "DELETE FROM c_paymentterm WHERE value='2-10-Net-45'" 2>/dev/null || true
fi

# 3. Record initial payment term count for verification baseline
INITIAL_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_paymentterm" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_count.txt
echo "Initial Payment Term count: $INITIAL_COUNT"

# 4. Ensure Firefox is running and navigate to iDempiere dashboard
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

# 5. Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png
echo "  Initial screenshot saved to /tmp/task_initial.png"

echo "=== configure_payment_term task setup complete ==="