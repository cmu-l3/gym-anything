#!/bin/bash
set -e
echo "=== Setting up Configure Shipping Provider Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded."

# 2. Cleanup: Remove 'Speedy Delivery' if it already exists to ensure a clean start
# We need to delete dependent Freight records first, then the Shipper
echo "Cleaning up any previous instances of 'Speedy Delivery'..."
CLIENT_ID=$(get_gardenworld_client_id)

# Delete M_Freight entries linked to Speedy Delivery
idempiere_query "DELETE FROM M_Freight WHERE M_Shipper_ID IN (SELECT M_Shipper_ID FROM M_Shipper WHERE Name='Speedy Delivery' AND AD_Client_ID=$CLIENT_ID)" 2>/dev/null || true

# Delete M_Shipper entry
idempiere_query "DELETE FROM M_Shipper WHERE Name='Speedy Delivery' AND AD_Client_ID=$CLIENT_ID" 2>/dev/null || true

# 3. Record initial count of Shippers
INITIAL_SHIPPER_COUNT=$(idempiere_query "SELECT COUNT(*) FROM M_Shipper WHERE AD_Client_ID=$CLIENT_ID" 2>/dev/null || echo "0")
echo "$INITIAL_SHIPPER_COUNT" > /tmp/initial_shipper_count.txt
echo "Initial shipper count: $INITIAL_SHIPPER_COUNT"

# 4. Ensure iDempiere is running and Firefox is ready
# Check if Firefox is running
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "Firefox not running, launching..."
    su - ga -c "DISPLAY=:1 firefox https://localhost:8443/webui/ &"
    sleep 15
else
    echo "Firefox is running."
fi

# Ensure we are at the dashboard (handles session timeouts/ZK dialogs)
navigate_to_dashboard

# Maximize window for visibility
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured."

echo "=== Task Setup Complete ==="