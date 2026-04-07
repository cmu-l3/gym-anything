#!/bin/bash
set -e
echo "=== Setting up Configure Product Replenishment task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ----------------------------------------------------------------
# 1. Clean up existing replenishment rules for Elm Tree @ HQ Warehouse
# ----------------------------------------------------------------
echo "--- Cleaning up previous state ---"

# Get IDs for cleanup
CLIENT_ID=$(get_gardenworld_client_id)
PRODUCT_ID=$(idempiere_query "SELECT m_product_id FROM m_product WHERE name='Elm Tree' AND ad_client_id=$CLIENT_ID" 2>/dev/null)
WAREHOUSE_ID=$(idempiere_query "SELECT m_warehouse_id FROM m_warehouse WHERE name='HQ Warehouse' AND ad_client_id=$CLIENT_ID" 2>/dev/null)

if [ -n "$PRODUCT_ID" ] && [ -n "$WAREHOUSE_ID" ]; then
    echo "  Found Product ID: $PRODUCT_ID, Warehouse ID: $WAREHOUSE_ID"
    # Delete existing replenishment rule if it exists
    idempiere_query "DELETE FROM m_replenish WHERE m_product_id=$PRODUCT_ID AND m_warehouse_id=$WAREHOUSE_ID" 2>/dev/null || true
    echo "  Cleaned up matching replenishment records."
else
    echo "  WARNING: Could not resolve IDs for cleanup. Product: '$PRODUCT_ID', Warehouse: '$WAREHOUSE_ID'"
fi

# ----------------------------------------------------------------
# 2. Ensure Application is Ready
# ----------------------------------------------------------------
echo "--- Ensuring iDempiere is ready ---"

# Ensure Firefox is running
if ! pgrep -f firefox > /dev/null; then
    echo "  Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox https://localhost:8443/webui/ &"
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "firefox"; then
            break
        fi
        sleep 1
    done
fi

# Navigate to dashboard to ensure clean UI state
navigate_to_dashboard

# Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="