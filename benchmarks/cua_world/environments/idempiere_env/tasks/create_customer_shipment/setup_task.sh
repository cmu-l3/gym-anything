#!/bin/bash
set -e
echo "=== Setting up create_customer_shipment task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Record initial shipment count for comparison
# We count customer shipments (issotrx='Y') for GardenWorld
CLIENT_ID=$(get_gardenworld_client_id)
INITIAL_COUNT=$(idempiere_query "SELECT COUNT(*) FROM m_inout WHERE issotrx='Y' AND ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_shipment_count.txt
echo "Initial shipment count: $INITIAL_COUNT"

# 3. Ensure prerequisites exist (sanity check)
# Check C&W Construction exists
CW_EXISTS=$(idempiere_query "SELECT COUNT(*) FROM c_bpartner WHERE name='C&W Construction' AND ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")
if [ "$CW_EXISTS" -eq 0 ]; then
    echo "WARNING: Business Partner 'C&W Construction' not found!"
fi

# 4. Ensure Firefox is running and showing iDempiere
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox https://localhost:8443/webui/ &"
    sleep 15
fi

# Navigate to Dashboard to ensure clean state
navigate_to_dashboard

# Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 5. Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="