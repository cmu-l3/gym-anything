#!/bin/bash
# Setup for "procure_receive_stock" task
# Ensures SDP is running and records initial state

echo "=== Setting up Procure & Receive Stock task ==="
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Record Task Start Time
date +%s > /tmp/task_start_time.txt

# 1. Ensure SDP is running (waits for install if needed)
ensure_sdp_running

# 2. Check for existing assets with target serials (to ensure clean slate or detect pre-existence)
echo "Checking for existing assets..."
EXISTING_ASSETS_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM Resources WHERE SERIALNO IN ('DELL-CAD-001', 'DELL-CAD-002', 'DELL-CAD-003');")
echo "$EXISTING_ASSETS_COUNT" > /tmp/initial_asset_count.txt
echo "Existing assets with target serials: $EXISTING_ASSETS_COUNT"

# 3. Clean up if they exist (best effort to prevent confusion, though complex due to FKs)
if [ "$EXISTING_ASSETS_COUNT" -gt 0 ]; then
    echo "WARNING: Target assets already exist. Attempting to clean..."
    # This is risky without cascading deletes, so we mostly rely on the timestamp check in verifier
    # and the agent creating a NEW PO.
fi

# 4. Open Firefox to the Purchases module
echo "Opening Firefox..."
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Purchase.do"
sleep 5

# 5. Capture Initial State
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Task: Procure 3 Dell Precision 3660 workstations from Dell Inc."
echo "Target Serials: DELL-CAD-001, 002, 003"