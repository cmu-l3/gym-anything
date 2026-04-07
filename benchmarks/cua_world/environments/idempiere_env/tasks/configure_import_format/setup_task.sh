#!/bin/bash
set -e
echo "=== Setting up configure_import_format task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 1. Clean up any previous attempts (Idempotency)
# We remove any Import Format with the specific name we are asking the agent to create
# to ensure we are verifying work done in *this* session.
echo "--- Cleaning up previous test data ---"
CLEANUP_QUERY="DELETE FROM ad_impformat WHERE name='Legacy Customer Import' AND ad_client_id=11;"
idempiere_query "$CLEANUP_QUERY" 2>/dev/null || true

# 2. Record initial count of Import Formats for GardenWorld
INITIAL_COUNT=$(idempiere_query "SELECT COUNT(*) FROM ad_impformat WHERE ad_client_id=11" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_count.txt
echo "Initial Import Format count: $INITIAL_COUNT"

# 3. Ensure iDempiere is running and Firefox is focused
echo "--- Ensuring iDempiere is ready ---"
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox https://localhost:8443/webui/ &"
    # Wait for startup
    sleep 15
fi

# Navigate to dashboard/home to ensure clean starting state
ensure_idempiere_open ""

# Maximize the window for better visibility
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="