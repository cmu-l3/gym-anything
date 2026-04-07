#!/bin/bash
set -e
echo "=== Setting up process_employee_expenses task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# ---------------------------------------------------------------
# 1. Clean up previous runs (Idempotency)
# ---------------------------------------------------------------
echo "--- Cleaning up any existing data for 'Alex Roadwarrior' ---"
CLIENT_ID=$(get_gardenworld_client_id)
if [ -z "$CLIENT_ID" ]; then CLIENT_ID=11; fi

# Deactivate any existing BP with this name to prevent unique constraint errors or ambiguity
# We append a timestamp to the name/value to free up the original keys
TS=$(date +%s)
idempiere_query "UPDATE c_bpartner SET isactive='N', value='OLD_${TS}_'||substring(value,1,20), name='OLD_${TS}_'||substring(name,1,40) WHERE name='Alex Roadwarrior' AND ad_client_id=$CLIENT_ID" 2>/dev/null || true

# ---------------------------------------------------------------
# 2. Record initial state
# ---------------------------------------------------------------
INITIAL_BP_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_bpartner WHERE isactive='Y' AND ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")
echo "$INITIAL_BP_COUNT" > /tmp/initial_bp_count.txt

INITIAL_EXP_COUNT=$(idempiere_query "SELECT COUNT(*) FROM s_timeexpense WHERE isactive='Y' AND ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")
echo "$INITIAL_EXP_COUNT" > /tmp/initial_exp_count.txt

# ---------------------------------------------------------------
# 3. Ensure Application is Ready
# ---------------------------------------------------------------
echo "--- Ensuring iDempiere is running and focused ---"

# Check if Firefox is running; if not, start it
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox https://localhost:8443/webui/ &"
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "firefox"; then break; fi
        sleep 1
    done
    sleep 10
fi

# Navigate to dashboard/home to ensure clean slate
ensure_idempiere_open ""

# Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="