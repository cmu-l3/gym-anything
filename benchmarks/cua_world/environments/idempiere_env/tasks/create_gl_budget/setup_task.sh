#!/bin/bash
set -e
echo "=== Setting up create_gl_budget task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Clean up any pre-existing budget with the target name to ensure a fresh start
# We use UPDATE IsActive='N' + renaming to avoid unique constraint violations if we can't hard delete
echo "--- Cleaning up old data ---"
CLIENT_ID=$(get_gardenworld_client_id)
if [ -n "$CLIENT_ID" ]; then
    # Rename old budgets to avoid name collision, and deactivate them
    idempiere_query "UPDATE gl_budget SET name=name||'_OLD_'||gl_budget_id, isactive='N' WHERE name='2025 Operating Budget' AND ad_client_id=$CLIENT_ID" 2>/dev/null || true
    echo "  Cleanup complete (client_id=$CLIENT_ID)"
else
    echo "  WARNING: Could not get GardenWorld client ID"
fi

# 2. Record initial budget count
INITIAL_COUNT=$(idempiere_query "SELECT COUNT(*) FROM gl_budget WHERE ad_client_id=${CLIENT_ID:-11} AND isactive='Y'" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_budget_count.txt
echo "Initial active budget count: $INITIAL_COUNT"

# 3. Ensure Firefox is running and navigate to iDempiere dashboard
echo "--- Navigating to iDempiere ---"
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "  Firefox not running, launching..."
    su - ga -c "DISPLAY=:1 firefox https://localhost:8443/webui/ &"
    # Wait for Firefox to really start
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "firefox"; then break; fi
        sleep 1
    done
    sleep 10
fi

# Navigate to iDempiere dashboard (handles ZK leave-page dialog automatically)
ensure_idempiere_open ""

# Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 3

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png
echo "  Initial screenshot saved to /tmp/task_initial.png"

echo "=== create_gl_budget task setup complete ==="