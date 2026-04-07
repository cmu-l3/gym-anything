#!/bin/bash
set -e
echo "=== Setting up create_sales_opportunity task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time (for anti-gaming and date calculation)
date +%s > /tmp/task_start_time.txt
date -I > /tmp/task_start_date.txt

# 2. Cleanup: Deactivate any previous attempts with this specific name to ensure clean state
echo "--- Cleaning up potential previous attempts ---"
CLIENT_ID=$(get_gardenworld_client_id)
if [ -n "$CLIENT_ID" ]; then
    idempiere_query "UPDATE C_Opportunity SET IsActive='N' WHERE Name='Oak Street Office Park' AND AD_Client_ID=$CLIENT_ID" 2>/dev/null || true
fi

# 3. Record initial opportunity count
INITIAL_COUNT=$(idempiere_query "SELECT COUNT(*) FROM C_Opportunity WHERE AD_Client_ID=${CLIENT_ID:-11} AND IsActive='Y'" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_opp_count.txt
echo "Initial Opportunity Count: $INITIAL_COUNT"

# 4. Ensure Firefox is running and navigate to dashboard
echo "--- Ensuring iDempiere is ready ---"
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "  Firefox not running, launching..."
    su - ga -c "DISPLAY=:1 firefox https://localhost:8443/webui/ &"
    
    # Wait for Firefox
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla"; then
            break
        fi
        sleep 1
    done
    sleep 10
else
    # Navigate to dashboard to ensure clean UI state
    ensure_idempiere_open ""
fi

# 5. Maximize and focus
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="