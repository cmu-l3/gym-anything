#!/bin/bash
set -e
echo "=== Setting up process_sales_payment_cycle task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record Task Start Time
date +%s > /tmp/task_start_time.txt

# 2. Record Initial Counts to detect new records later
CLIENT_ID=$(get_gardenworld_client_id)
# Default to 11 if query fails
CLIENT_ID=${CLIENT_ID:-11}

echo "Client ID: $CLIENT_ID"

# Count existing invoices for Joe Block
INITIAL_INV_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_invoice i JOIN c_bpartner bp ON i.c_bpartner_id=bp.c_bpartner_id WHERE bp.name='Joe Block' AND i.ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")
echo "$INITIAL_INV_COUNT" > /tmp/initial_inv_count.txt

# Count existing payments for Joe Block
INITIAL_PAY_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_payment p JOIN c_bpartner bp ON p.c_bpartner_id=bp.c_bpartner_id WHERE bp.name='Joe Block' AND p.ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")
echo "$INITIAL_PAY_COUNT" > /tmp/initial_pay_count.txt

# Count existing allocations
INITIAL_ALLOC_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_allocationhdr WHERE ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")
echo "$INITIAL_ALLOC_COUNT" > /tmp/initial_alloc_count.txt

# 3. Ensure iDempiere is running and Firefox is open
echo "--- Ensuring iDempiere is ready ---"
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox https://localhost:8443/webui/ &"
    sleep 15
fi

# Navigate to dashboard to ensure clean slate
navigate_to_dashboard

# Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="