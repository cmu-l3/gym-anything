#!/bin/bash
set -e
echo "=== Setting up create_financial_year task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Cleanup: Remove Year 2030 if it exists to ensure clean state
# We must remove periods first due to FK constraints
echo "--- Cleaning up any existing 2030 data ---"
CLIENT_ID=$(get_gardenworld_client_id)

# Get C_Year_ID for 2030 if it exists
YEAR_ID=$(idempiere_query "SELECT c_year_id FROM c_year WHERE fiscalyear='2030' AND ad_client_id=$CLIENT_ID" 2>/dev/null || echo "")

if [ -n "$YEAR_ID" ] && [ "$YEAR_ID" != "0" ]; then
    echo "  Found existing year 2030 (ID: $YEAR_ID). Deleting..."
    # Delete periods
    idempiere_query "DELETE FROM c_period WHERE c_year_id=$YEAR_ID" 2>/dev/null || true
    # Delete year
    idempiere_query "DELETE FROM c_year WHERE c_year_id=$YEAR_ID" 2>/dev/null || true
else
    echo "  No existing 2030 year found."
fi

# 3. Ensure Firefox is running and navigate to iDempiere
echo "--- Navigating to iDempiere ---"
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "  Firefox not running, launching..."
    su - ga -c "DISPLAY=:1 firefox https://localhost:8443/webui/ &"
    sleep 15
fi

# Navigate to iDempiere dashboard
ensure_idempiere_open ""

# Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="