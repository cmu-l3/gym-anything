#!/bin/bash
set -e
echo "=== Setting up register_fixed_asset task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Clean up any previous attempts (Deactivate existing asset with this key)
# We don't delete to preserve referential integrity, just set to inactive/change key
echo "--- Cleaning up previous test data ---"
CLIENT_ID=$(get_gardenworld_client_id)
if [ -z "$CLIENT_ID" ]; then CLIENT_ID=11; fi

# Rename old asset if it exists so we can create a new one with the same key
idempiere_query "UPDATE a_asset SET value=value||'_old_'||to_char(now(),'YYYYMMDDHH24MISS'), isactive='N' WHERE value='TRUCK-2024-001' AND ad_client_id=$CLIENT_ID" 2>/dev/null || true

# 3. Record initial asset count
INITIAL_COUNT=$(idempiere_query "SELECT COUNT(*) FROM a_asset WHERE ad_client_id=$CLIENT_ID AND isactive='Y'" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_asset_count.txt
echo "Initial Asset Count: $INITIAL_COUNT"

# 4. Ensure iDempiere is running and Firefox is focused
echo "--- Ensuring Application State ---"

# Check if Firefox is running
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox https://localhost:8443/webui/ &"
    sleep 15
fi

# Navigate to dashboard/home
navigate_to_dashboard

# Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# 5. Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="