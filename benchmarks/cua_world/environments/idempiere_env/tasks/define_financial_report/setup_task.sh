#!/bin/bash
set -e
echo "=== Setting up define_financial_report task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Clean up previous runs (Idempotency)
# We remove any existing report definitions with these specific names to ensure we verify new work
echo "--- Cleaning up existing test data ---"
CLIENT_ID=$(get_gardenworld_client_id)

# Delete in reverse dependency order (Report -> Lines/Columns)
if [ -n "$CLIENT_ID" ]; then
    idempiere_query "DELETE FROM pa_report WHERE name='GP Board Report' AND ad_client_id=$CLIENT_ID" 2>/dev/null || true
    idempiere_query "DELETE FROM pa_reportlineset WHERE name='Gross Profit Analysis' AND ad_client_id=$CLIENT_ID" 2>/dev/null || true
    idempiere_query "DELETE FROM pa_reportcolumnset WHERE name='Current Period Analysis' AND ad_client_id=$CLIENT_ID" 2>/dev/null || true
    echo "  Cleanup complete"
fi

# 2. Record initial counts (just in case)
INITIAL_REPORT_COUNT=$(idempiere_query "SELECT COUNT(*) FROM pa_report WHERE ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")
echo "$INITIAL_REPORT_COUNT" > /tmp/initial_report_count.txt

# 3. Ensure Firefox is running and navigate to iDempiere dashboard
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