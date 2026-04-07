#!/bin/bash
set -e
echo "=== Setting up procure_to_pay_cycle task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record Task Start Time
date +%s > /tmp/task_start_time.txt

# 2. Get GardenWorld Client ID
CLIENT_ID=$(get_gardenworld_client_id)
CLIENT_ID=${CLIENT_ID:-11}
echo "Client ID: $CLIENT_ID"

# 3. Record Initial Counts to detect new records later
# Purchase Orders (issotrx='N' in c_order)
INITIAL_PO_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_order WHERE issotrx='N' AND ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")
echo "$INITIAL_PO_COUNT" > /tmp/initial_po_count.txt
echo "Initial PO count: $INITIAL_PO_COUNT"

# Material Receipts (issotrx='N' in m_inout)
INITIAL_RECEIPT_COUNT=$(idempiere_query "SELECT COUNT(*) FROM m_inout WHERE issotrx='N' AND ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")
echo "$INITIAL_RECEIPT_COUNT" > /tmp/initial_receipt_count.txt
echo "Initial Receipt count: $INITIAL_RECEIPT_COUNT"

# Vendor Invoices (issotrx='N' in c_invoice)
INITIAL_INV_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_invoice WHERE issotrx='N' AND ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")
echo "$INITIAL_INV_COUNT" > /tmp/initial_inv_count.txt
echo "Initial Invoice count: $INITIAL_INV_COUNT"

# Payments (outgoing, isreceipt='N')
INITIAL_PAY_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_payment WHERE isreceipt='N' AND ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")
echo "$INITIAL_PAY_COUNT" > /tmp/initial_pay_count.txt
echo "Initial Payment count: $INITIAL_PAY_COUNT"

# Allocations
INITIAL_ALLOC_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_allocationhdr WHERE ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")
echo "$INITIAL_ALLOC_COUNT" > /tmp/initial_alloc_count.txt
echo "Initial Allocation count: $INITIAL_ALLOC_COUNT"

# 4. Verify Master Data Availability
# Check vendor exists
VENDOR_CHECK=$(idempiere_query "SELECT COUNT(*) FROM c_bpartner WHERE name='Tree Farm Inc.' AND ad_client_id=$CLIENT_ID AND isactive='Y'" 2>/dev/null || echo "0")
if [ "$VENDOR_CHECK" -eq "0" ]; then
    echo "WARNING: Vendor 'Tree Farm Inc.' not found!"
else
    echo "Vendor 'Tree Farm Inc.' found."
fi

# Check products exist
OAK_CHECK=$(idempiere_query "SELECT COUNT(*) FROM m_product WHERE name='Oak Tree' AND ad_client_id=$CLIENT_ID AND isactive='Y'" 2>/dev/null || echo "0")
HOLLY_CHECK=$(idempiere_query "SELECT COUNT(*) FROM m_product WHERE name='Holly Bush' AND ad_client_id=$CLIENT_ID AND isactive='Y'" 2>/dev/null || echo "0")
echo "Product checks - Oak Tree: $OAK_CHECK, Holly Bush: $HOLLY_CHECK"

# Check bank account exists
BANK_CHECK=$(idempiere_query "SELECT COUNT(*) FROM c_bankaccount ba JOIN c_bank b ON ba.c_bank_id=b.c_bank_id WHERE ba.ad_client_id=$CLIENT_ID AND ba.isactive='Y'" 2>/dev/null || echo "0")
echo "Bank account check: $BANK_CHECK active accounts found"

# 5. Delete any stale output files
rm -f /tmp/procure_to_pay_cycle_result.json 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# 6. Ensure iDempiere is running and Firefox is open
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

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
