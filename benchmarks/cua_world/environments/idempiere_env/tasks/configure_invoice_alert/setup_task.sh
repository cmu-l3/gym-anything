#!/bin/bash
set -e
echo "=== Setting up configure_invoice_alert task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Clean up any pre-existing alert with the target name to ensure clean state
echo "--- Cleaning up pre-existing alerts ---"
CLIENT_ID=$(get_gardenworld_client_id)
# Note: AD_Alert is a system table but data is often client-specific or filtered.
# We'll try to deactivate any alert with this specific name in the GardenWorld client context.
if [ -n "$CLIENT_ID" ]; then
    idempiere_query "UPDATE ad_alert SET isactive='N' WHERE name='High Value Purchase' AND ad_client_id=$CLIENT_ID" 2>/dev/null || true
    echo "  Cleanup attempt complete"
fi

# 2. Record initial alert count for debugging
INITIAL_ALERT_COUNT=$(idempiere_query "SELECT COUNT(*) FROM ad_alert WHERE name='High Value Purchase' AND isactive='Y' AND ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")
echo "Initial specific alert count: $INITIAL_ALERT_COUNT"

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
take_screenshot /tmp/task_initial.png
echo "  Initial screenshot saved to /tmp/task_initial.png"

echo "=== Task setup complete ==="