#!/bin/bash
echo "=== Setting up create_warehouse task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 1. Clean up any previous runs (delete specific warehouse and locators)
echo "--- Cleaning up previous data ---"
# We need to find the ID first to delete children, or use cascade if configured, 
# but safely we delete locators first.
WAREHOUSE_ID=$(idempiere_query "SELECT m_warehouse_id FROM m_warehouse WHERE value='GW-WDC'" 2>/dev/null || echo "")

if [ -n "$WAREHOUSE_ID" ] && [ "$WAREHOUSE_ID" != "0" ]; then
    echo "  Deleting existing locators for warehouse ID $WAREHOUSE_ID..."
    idempiere_query "DELETE FROM m_locator WHERE m_warehouse_id=$WAREHOUSE_ID" 2>/dev/null || true
    echo "  Deleting existing warehouse..."
    idempiere_query "DELETE FROM m_warehouse WHERE m_warehouse_id=$WAREHOUSE_ID" 2>/dev/null || true
fi

# 2. Verify cleanup
REMAINING=$(idempiere_query "SELECT COUNT(*) FROM m_warehouse WHERE value='GW-WDC'" 2>/dev/null || echo "0")
echo "  Remaining warehouses with key GW-WDC: $REMAINING"

# 3. Ensure Firefox is running and navigate to dashboard
echo "--- Preparing iDempiere UI ---"
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "  Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox https://localhost:8443/webui/ &"
    sleep 15
fi

# Navigate to dashboard to ensure clean UI state
ensure_idempiere_open ""

# Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="