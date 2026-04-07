#!/bin/bash
set -e
echo "=== Setting up configure_gl_distribution task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming (timestamp check)
date +%s > /tmp/task_start_time.txt

# 1. Clean up any data from previous runs to ensure clean state
echo "--- Cleaning up previous run data ---"
CLIENT_ID=$(get_gardenworld_client_id)
if [ -n "$CLIENT_ID" ]; then
    # Delete Distribution (Cascades to lines usually, but we do explicitly to be safe)
    idempiere_query "DELETE FROM gl_distribution WHERE name='Marketing Split 2025' AND ad_client_id=$CLIENT_ID" 2>/dev/null || true
    
    # Delete Campaigns
    idempiere_query "DELETE FROM c_campaign WHERE value IN ('SPRING2025', 'SUMMER2025') AND ad_client_id=$CLIENT_ID" 2>/dev/null || true
    
    echo "  Cleanup complete."
else
    echo "  WARNING: Could not get GardenWorld client ID - cleanup may have failed."
fi

# 2. Ensure Firefox is running and navigate to iDempiere dashboard
echo "--- Navigating to iDempiere ---"
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "  Firefox not running, launching..."
    su - ga -c "DISPLAY=:1 firefox https://localhost:8443/webui/ &"
    sleep 15
fi

# Navigate to iDempiere dashboard
ensure_idempiere_open ""

# Maximize window for visibility
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 3

# 3. Take initial screenshot
take_screenshot /tmp/task_initial.png
echo "  Initial screenshot saved to /tmp/task_initial.png"

echo "=== Setup complete ==="