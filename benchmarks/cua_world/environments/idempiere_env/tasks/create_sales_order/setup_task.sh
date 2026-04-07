#!/bin/bash
echo "=== Setting up create_sales_order task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record initial sales order count
CLIENT_ID=$(get_gardenworld_client_id)
INITIAL_ORDER_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_order WHERE issotrx='Y' AND ad_client_id=${CLIENT_ID:-11}" 2>/dev/null || echo "0")
echo "Initial sales order count: $INITIAL_ORDER_COUNT"
rm -f /tmp/initial_sales_order_count.txt 2>/dev/null || true
echo "$INITIAL_ORDER_COUNT" > /tmp/initial_sales_order_count.txt
chmod 666 /tmp/initial_sales_order_count.txt 2>/dev/null || true

# 2. Verify prerequisite data exists: C&W Construction and required products
echo "--- Verifying prerequisite GardenWorld demo data ---"
CW_BP=$(idempiere_query "SELECT name FROM c_bpartner WHERE name ILIKE '%C&W%' AND ad_client_id=${CLIENT_ID:-11} AND isactive='Y' LIMIT 1" 2>/dev/null || echo "")
echo "  C&W Construction found: '${CW_BP}'"

MULCH=$(idempiere_query "SELECT name FROM m_product WHERE name='Mulch 10#' AND ad_client_id=${CLIENT_ID:-11} AND isactive='Y' LIMIT 1" 2>/dev/null || echo "")
echo "  'Mulch 10#' product found: '${MULCH}'"

FERT=$(idempiere_query "SELECT name FROM m_product WHERE name='Fertilizer #50' AND ad_client_id=${CLIENT_ID:-11} AND isactive='Y' LIMIT 1" 2>/dev/null || echo "")
echo "  'Fertilizer #50' product found: '${FERT}'"

# 3. Ensure Firefox is running and navigate to iDempiere dashboard
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
take_screenshot /tmp/create_sales_order_initial.png
echo "  Initial screenshot saved to /tmp/create_sales_order_initial.png"

echo "=== create_sales_order task setup complete ==="
echo "Task: Create Sales Order for C&W Construction with 'Mulch 10#' (qty 10) and 'Fertilizer #50' (qty 5)"
echo "Navigation hint: Menu > Quote-to-Invoice > Sales Order > New Record"
