#!/bin/bash
echo "=== Setting up create_purchase_order task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record initial purchase order count
CLIENT_ID=$(get_gardenworld_client_id)
INITIAL_PO_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_order WHERE issotrx='N' AND ad_client_id=${CLIENT_ID:-11}" 2>/dev/null || echo "0")
echo "Initial purchase order count: $INITIAL_PO_COUNT"
rm -f /tmp/initial_po_count.txt 2>/dev/null || true
echo "$INITIAL_PO_COUNT" > /tmp/initial_po_count.txt
chmod 666 /tmp/initial_po_count.txt 2>/dev/null || true

# 2. Verify prerequisite vendor exists
echo "--- Verifying prerequisite GardenWorld demo data ---"
SEED_FARM=$(idempiere_query "SELECT name FROM c_bpartner WHERE name='Seed Farm Inc.' AND ad_client_id=${CLIENT_ID:-11} AND isactive='Y' AND isvendor='Y' LIMIT 1" 2>/dev/null || echo "")
echo "  Seed Farm vendor found: '${SEED_FARM}'"

# Also show all vendors for reference
echo "  All active vendors:"
idempiere_query "SELECT name FROM c_bpartner WHERE ad_client_id=${CLIENT_ID:-11} AND isactive='Y' AND isvendor='Y' ORDER BY name" 2>/dev/null || true

# 3. Ensure Firefox is running and navigate to iDempiere
echo "--- Navigating to iDempiere ---"
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

# 4. Take initial screenshot
take_screenshot /tmp/create_purchase_order_initial.png
echo "  Initial screenshot saved to /tmp/create_purchase_order_initial.png"

echo "=== create_purchase_order task setup complete ==="
echo "Task: Create Purchase Order for Seed Farm with Compost (qty 50) and Mulch (qty 100)"
echo "Navigation hint: Menu > Requisition-to-Invoice > Purchase Order > New Record"
