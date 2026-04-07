#!/bin/bash
set -e
echo "=== Setting up create_uom_conversion task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Clean up any pre-existing UOM with symbol BX24 to ensure clean state
echo "--- Cleaning up previous data ---"
CLIENT_ID=$(get_gardenworld_client_id)
# Deactivate conversion first (child record)
idempiere_query "UPDATE c_uom_conversion SET isactive='N' WHERE c_uom_id IN (SELECT c_uom_id FROM c_uom WHERE uomsymbol='BX24' AND ad_client_id=$CLIENT_ID)" 2>/dev/null || true
# Deactivate UOM
idempiere_query "UPDATE c_uom SET isactive='N', uomsymbol='BX24_OLD_'||c_uom_id WHERE uomsymbol='BX24' AND ad_client_id=$CLIENT_ID" 2>/dev/null || true

# 2. Record initial UOM count (for anti-gaming)
INITIAL_UOM_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_uom WHERE ad_client_id=$CLIENT_ID AND isactive='Y'" 2>/dev/null || echo "0")
echo "$INITIAL_UOM_COUNT" > /tmp/initial_uom_count.txt

# 3. Ensure Firefox is running and navigate to Dashboard
echo "--- Checking Firefox ---"
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox https://localhost:8443/webui/ &"
    sleep 15
fi

# Navigate to iDempiere dashboard (handles ZK leave-page dialog automatically)
ensure_idempiere_open ""

# Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="