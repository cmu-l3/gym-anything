#!/bin/bash
set -e
echo "=== Setting up register_bank_account task ==="

# Source shared utilities for iDempiere interaction
source /workspace/scripts/task_utils.sh

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Clean up any pre-existing test data to ensure a clean state
# We deactivate and rename any existing bank with the target name or routing number
# to prevent unique constraint violations if the agent tries to create it again.
echo "--- Cleaning up pre-existing test data ---"
CLIENT_ID=$(get_gardenworld_client_id)
if [ -n "$CLIENT_ID" ]; then
    # Deactivate and rename old banks to avoid conflict
    idempiere_query "UPDATE c_bank SET isactive='N', name=name||'_old_'||to_char(now(),'YYYYMMDDHH24MISS'), routingno=routingno||'_old' WHERE (name='Metro City Bank' OR routingno='021000021') AND ad_client_id=$CLIENT_ID" 2>/dev/null || true
    echo "  Cleanup complete (client_id=$CLIENT_ID)"
else
    echo "  WARNING: Could not get GardenWorld client ID"
fi

# 3. Record initial bank count for verification baseline
INITIAL_BANK_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_bank WHERE ad_client_id=${CLIENT_ID:-11} AND isactive='Y'" 2>/dev/null || echo "0")
echo "$INITIAL_BANK_COUNT" > /tmp/initial_bank_count.txt
echo "Initial active bank count: $INITIAL_BANK_COUNT"

# 4. Ensure Firefox is running and navigate to iDempiere dashboard
echo "--- Navigating to iDempiere dashboard ---"
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "  Firefox not running, launching..."
    su - ga -c "DISPLAY=:1 firefox https://localhost:8443/webui/ &"
    # Wait for Firefox and iDempiere to load
    sleep 15
fi

# Navigate to iDempiere dashboard (handles ZK "leave page" dialog automatically)
ensure_idempiere_open ""

# 5. Maximize window to ensure all UI elements are visible
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 3

# 6. Take initial screenshot for evidence
take_screenshot /tmp/register_bank_account_initial.png
echo "  Initial screenshot saved to /tmp/register_bank_account_initial.png"

echo "=== register_bank_account task setup complete ==="
echo "Task: Register 'Metro City Bank' (Routing: 021000021) and account 'Payroll Checking' (Acct: 888999000)"