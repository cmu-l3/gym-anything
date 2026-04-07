#!/bin/bash
set -e
echo "=== Setting up procure_to_pay_with_landed_cost task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record Task Start Time
date +%s > /tmp/task_start_time.txt

# 2. Get Client ID for GardenWorld
CLIENT_ID=$(get_gardenworld_client_id)
CLIENT_ID=${CLIENT_ID:-11}
echo "Client ID: $CLIENT_ID"

# 3. Record initial counts to detect new records created during the task
# Purchase Orders
INITIAL_PO_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_order WHERE issotrx='N' AND ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")
echo "$INITIAL_PO_COUNT" > /tmp/initial_po_count.txt

# Material Receipts
INITIAL_RECEIPT_COUNT=$(idempiere_query "SELECT COUNT(*) FROM m_inout WHERE issotrx='N' AND ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")
echo "$INITIAL_RECEIPT_COUNT" > /tmp/initial_receipt_count.txt

# Vendor Invoices
INITIAL_INVOICE_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_invoice WHERE issotrx='N' AND ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")
echo "$INITIAL_INVOICE_COUNT" > /tmp/initial_invoice_count.txt

# Payments
INITIAL_PAYMENT_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_payment WHERE isreceipt='N' AND ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")
echo "$INITIAL_PAYMENT_COUNT" > /tmp/initial_payment_count.txt

# Landed Cost Allocations
INITIAL_LCA_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_landedcostallocation WHERE ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")
echo "$INITIAL_LCA_COUNT" > /tmp/initial_lca_count.txt

# Payment Allocations
INITIAL_ALLOC_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_allocationhdr WHERE ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")
echo "$INITIAL_ALLOC_COUNT" > /tmp/initial_alloc_count.txt

echo "Initial Counts - POs: $INITIAL_PO_COUNT, Receipts: $INITIAL_RECEIPT_COUNT, Invoices: $INITIAL_INVOICE_COUNT, Payments: $INITIAL_PAYMENT_COUNT, LCA: $INITIAL_LCA_COUNT, Alloc: $INITIAL_ALLOC_COUNT"

# 4. Verify prerequisite master data exists
echo "--- Verifying prerequisite GardenWorld demo data ---"

# Check Seed Farm Inc. vendor
VENDOR_CHECK=$(idempiere_query "SELECT name FROM c_bpartner WHERE name='Seed Farm Inc.' AND ad_client_id=$CLIENT_ID AND isactive='Y' AND isvendor='Y' LIMIT 1" 2>/dev/null || echo "")
echo "  Vendor 'Seed Farm Inc.': '${VENDOR_CHECK}'"

# Check Azalea Bush product
PRODUCT_CHECK=$(idempiere_query "SELECT name FROM m_product WHERE name='Azalea Bush' AND ad_client_id=$CLIENT_ID AND isactive='Y' LIMIT 1" 2>/dev/null || echo "")
echo "  Product 'Azalea Bush': '${PRODUCT_CHECK}'"

# Check Freight Charges charge exists
FREIGHT_CHECK=$(idempiere_query "SELECT name FROM c_charge WHERE name='Freight Charges' AND ad_client_id=$CLIENT_ID AND isactive='Y' LIMIT 1" 2>/dev/null || echo "")
echo "  Charge 'Freight Charges': '${FREIGHT_CHECK}'"

# 5. Delete any stale output files from previous runs
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/task_final.png 2>/dev/null || true

# 6. Ensure Firefox is running and navigate to iDempiere
echo "--- Navigating to iDempiere ---"
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "  Firefox not running, launching..."
    su - ga -c "DISPLAY=:1 firefox https://localhost:8443/webui/ &"
    sleep 15
fi

# Navigate to iDempiere dashboard (handles ZK leave-page dialog)
ensure_idempiere_open ""

# Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 3

# 7. Capture initial state screenshot
take_screenshot /tmp/task_initial.png
echo "  Initial screenshot saved to /tmp/task_initial.png"

echo "=== procure_to_pay_with_landed_cost task setup complete ==="
echo "Task: Complete P2P cycle with landed cost for Seed Farm Inc. / Azalea Bush"
echo "Navigation hints:"
echo "  - Purchase Order: Menu > Requisition-to-Invoice > Purchase Order"
echo "  - Material Receipt: Menu > Requisition-to-Invoice > Material Receipt"
echo "  - Vendor Invoice: Menu > Requisition-to-Invoice > Invoice (Vendor)"
echo "  - Landed Cost: Menu > Requisition-to-Invoice > Landed Cost Distribution"
echo "  - Payment: Menu > Open Items > Payment"
