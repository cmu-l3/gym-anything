#!/bin/bash
set -e
echo "=== Setting up prepare_payment_batch task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming (PostgreSQL timestamp comparison)
# iDempiere stores timestamps in DB. We'll use this to filter records created during the task.
date +%s > /tmp/task_start_time.txt
echo "Task start timestamp: $(cat /tmp/task_start_time.txt)"

# 2. Record initial counts to help debugging
CLIENT_ID=$(get_gardenworld_client_id)
INITIAL_INV_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_invoice WHERE issotrx='N' AND ad_client_id=${CLIENT_ID:-11}" 2>/dev/null || echo "0")
INITIAL_PAYSEL_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_payselection WHERE ad_client_id=${CLIENT_ID:-11}" 2>/dev/null || echo "0")

echo "Initial Vendor Invoices: $INITIAL_INV_COUNT"
echo "Initial Payment Selections: $INITIAL_PAYSEL_COUNT"

# 3. Ensure Firefox is running and navigate to iDempiere dashboard
echo "--- Navigating to iDempiere ---"
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "  Firefox not running, launching..."
    su - ga -c "DISPLAY=:1 firefox https://localhost:8443/webui/ &"
    sleep 15
fi

# Navigate to iDempiere dashboard (handles ZK leave-page dialog automatically)
ensure_idempiere_open ""

# Maximize window to ensure all buttons/tabs are visible
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 3

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png
echo "  Initial screenshot saved to /tmp/task_initial.png"

echo "=== Setup complete ==="