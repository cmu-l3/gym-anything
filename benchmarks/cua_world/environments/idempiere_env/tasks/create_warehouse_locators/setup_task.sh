#!/bin/bash
set -e
echo "=== Setting up create_warehouse_locators task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 1. Clean up any pre-existing test data (Idempotency)
echo "--- Cleaning up stale locator data ---"
# We delete (or de-activate) any locators with these specific values to ensure a clean slate
# Note: In a real ERP deleting might be restricted if used, but for setup we try to clear 'em
# Using SQL to deactivate matches in HQ Warehouse
# Get HQ Warehouse ID
WAREHOUSE_ID=$(idempiere_query "SELECT m_warehouse_id FROM m_warehouse WHERE name LIKE 'HQ%' LIMIT 1" 2>/dev/null)

if [ -n "$WAREHOUSE_ID" ]; then
    echo "  Target Warehouse ID: $WAREHOUSE_ID"
    # Deactivate existing target locators
    idempiere_query "UPDATE m_locator SET isactive='N', value=value||'_old_'||to_char(now(),'HHMISS') WHERE m_warehouse_id=$WAREHOUSE_ID AND value IN ('OV-01-01', 'OV-01-02', 'OV-01-03')" 2>/dev/null || true
else
    echo "  WARNING: HQ Warehouse not found via query."
fi

# 2. Record initial locator count for HQ Warehouse
INITIAL_COUNT=$(idempiere_query "SELECT COUNT(*) FROM m_locator WHERE m_warehouse_id=$WAREHOUSE_ID AND isactive='Y'" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_locator_count.txt
echo "  Initial active locators in HQ: $INITIAL_COUNT"

# 3. Ensure Firefox is running and navigate to iDempiere
echo "--- Ensuring iDempiere is ready ---"
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "  Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox https://localhost:8443/webui/ &"
    sleep 15
fi

# Navigate to dashboard to ensure clean UI state
navigate_to_dashboard

# Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="