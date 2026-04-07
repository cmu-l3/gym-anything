#!/bin/bash
echo "=== Setting up create_rma task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Get GardenWorld Client ID
CLIENT_ID=$(get_gardenworld_client_id)
if [ -z "$CLIENT_ID" ]; then
    CLIENT_ID=11
    echo "Warning: Could not fetch Client ID, defaulting to 11"
fi

# 3. Record initial RMA count
INITIAL_RMA_COUNT=$(idempiere_query "SELECT COUNT(*) FROM m_rma WHERE ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")
echo "$INITIAL_RMA_COUNT" > /tmp/initial_rma_count.txt
echo "Initial RMA count: $INITIAL_RMA_COUNT"

# 4. Verify Data Pre-requisites (C&W Construction must exist and have shipments)
echo "--- Verifying C&W Construction Data ---"
BP_Check=$(idempiere_query "SELECT c_bpartner_id FROM c_bpartner WHERE name LIKE 'C&W Construction%' AND ad_client_id=$CLIENT_ID LIMIT 1")

if [ -z "$BP_Check" ]; then
    echo "ERROR: C&W Construction business partner not found!"
    # Fallback or exit? For this task, we assume standard seed data.
    # In a real scenario, we might create it here.
else
    echo "Found C&W Construction ID: $BP_Check"
    
    # Check for shipments
    SHIPMENT_COUNT=$(idempiere_query "SELECT COUNT(*) FROM m_inout WHERE c_bpartner_id=$BP_Check AND issotrx='Y' AND docstatus IN ('CO','CL')")
    echo "Found $SHIPMENT_COUNT completed shipments for C&W Construction."
    
    if [ "$SHIPMENT_COUNT" -eq "0" ]; then
        echo "WARNING: No shipments found for C&W. Task might be impossible via GUI referencing."
    fi
fi

# 5. Ensure Firefox is running and navigate to dashboard
echo "--- Navigating to iDempiere ---"
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "  Firefox not running, launching..."
    su - ga -c "DISPLAY=:1 firefox https://localhost:8443/webui/ &"
    sleep 15
fi

# Navigate to dashboard
ensure_idempiere_open ""

# Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 3

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured."

echo "=== Task setup complete ==="