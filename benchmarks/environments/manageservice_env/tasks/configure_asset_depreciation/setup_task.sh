#!/bin/bash
set -e
echo "=== Setting up Configure Asset Depreciation Task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure SDP is running (this handles waiting for install if needed)
ensure_sdp_running

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Clean State: Remove any existing depreciation info for 'Workstation'
# This ensures the agent must actually create/configure it, not just find it already done.
echo "Clearing existing depreciation settings for Workstation..."

# We attempt to find the ID for 'Workstation' and delete related depreciation info.
# Note: Table names in SDP are typically lower case in Postgres.
# Schema guess: producttype (typeid, typename), depreciationinfo (producttypeid, ...)

CLEAN_SQL="
DO \$\$
DECLARE
    ws_type_id integer;
BEGIN
    -- Try to find the Workstation product type ID
    SELECT typeid INTO ws_type_id FROM producttype WHERE typename = 'Workstation' LIMIT 1;
    
    IF ws_type_id IS NOT NULL THEN
        -- Delete existing depreciation info for this type
        DELETE FROM depreciationinfo WHERE producttypeid = ws_type_id;
        RAISE NOTICE 'Deleted depreciation info for type ID %', ws_type_id;
    END IF;
END \$\$;
"

sdp_db_exec "$CLEAN_SQL" || echo "Warning: DB cleanup query failed, strictly checking timestamps might be needed."

# 4. Prepare Firefox
echo "Launching Firefox..."
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Login.do"

# 5. Capture initial state
sleep 5
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="