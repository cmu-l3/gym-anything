#!/bin/bash
set -e
echo "=== Setting up record_production_run task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Record initial production count to detect new records later
CLIENT_ID=$(get_gardenworld_client_id)
# M_Production table stores production headers
INITIAL_COUNT=$(idempiere_query "SELECT COUNT(*) FROM m_production WHERE ad_client_id=${CLIENT_ID:-11}" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_production_count.txt
echo "Initial production record count: $INITIAL_COUNT"

# 3. Ensure iDempiere is running and accessible
echo "--- Ensuring iDempiere is ready ---"
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "  Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox https://localhost:8443/webui/ &"
    sleep 15
fi

# Navigate to dashboard/home to ensure clean state
# This function handles the ZK "Leave Page?" dialog if it appears
ensure_idempiere_open ""

# 4. Maximize window for agent visibility
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="