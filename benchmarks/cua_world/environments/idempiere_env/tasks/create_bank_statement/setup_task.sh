#!/bin/bash
echo "=== Setting up create_bank_statement task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
# Also record readable time for DB comparison if needed
date -Iseconds > /tmp/task_start_iso.txt

# 1. Record initial bank statement count
# We focus on GardenWorld client (ID 11 usually)
CLIENT_ID=$(get_gardenworld_client_id)
INITIAL_BS_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_bankstatement WHERE ad_client_id=${CLIENT_ID:-11}" 2>/dev/null || echo "0")
echo "Initial bank statement count: $INITIAL_BS_COUNT"
echo "$INITIAL_BS_COUNT" > /tmp/initial_bs_count.txt

# 2. Cleanup (Optional but good practice):
# Check if a statement with the target name already exists from a previous run and try to flag it
# We can't easily delete in iDempiere without cascading, but we can rename it to avoid confusion
EXISTING_ID=$(idempiere_query "SELECT c_bankstatement_id FROM c_bankstatement WHERE name='Dec 2024 Mid-Month Statement' AND ad_client_id=${CLIENT_ID:-11} LIMIT 1" 2>/dev/null)
if [ -n "$EXISTING_ID" ] && [ "$EXISTING_ID" != "" ]; then
    echo "Found existing statement with target name (ID: $EXISTING_ID). Renaming to avoid conflict..."
    idempiere_query "UPDATE c_bankstatement SET name='OLD_RUN_' || name, description='Renamed by setup script' WHERE c_bankstatement_id=$EXISTING_ID"
fi

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