#!/bin/bash
set -e
echo "=== Setting up process_landed_cost task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Get Client ID for GardenWorld
CLIENT_ID=$(get_gardenworld_client_id)
echo "Client ID: $CLIENT_ID" > /tmp/client_id.txt

# 3. Record initial counts to detect new records later
# Count Material Receipts (M_InOut where issotrx='N')
INITIAL_RECEIPT_COUNT=$(idempiere_query "SELECT COUNT(*) FROM m_inout WHERE issotrx='N' AND ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")
echo "$INITIAL_RECEIPT_COUNT" > /tmp/initial_receipt_count.txt

# Count Vendor Invoices (C_Invoice where issotrx='N')
INITIAL_INVOICE_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_invoice WHERE issotrx='N' AND ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")
echo "$INITIAL_INVOICE_COUNT" > /tmp/initial_invoice_count.txt

# Count Landed Cost Allocations
INITIAL_ALLOC_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_landedcostallocation WHERE ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")
echo "$INITIAL_ALLOC_COUNT" > /tmp/initial_alloc_count.txt

echo "Initial Counts - Receipts: $INITIAL_RECEIPT_COUNT, Invoices: $INITIAL_INVOICE_COUNT, Allocations: $INITIAL_ALLOC_COUNT"

# 4. Verify Master Data Availability
# Check if Oak Tree exists
OAK_TREE_CHECK=$(idempiere_query "SELECT count(*) FROM m_product WHERE value='Oak' AND ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")
if [ "$OAK_TREE_CHECK" -eq "0" ]; then
    echo "WARNING: Product 'Oak' not found. Agent might struggle."
fi

# 5. Launch Application
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

# 6. Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="