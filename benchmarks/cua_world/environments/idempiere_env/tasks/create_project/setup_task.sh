#!/bin/bash
set -e
echo "=== Setting up create_project task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Get GardenWorld Client ID
CLIENT_ID=$(get_gardenworld_client_id)
if [ -z "$CLIENT_ID" ]; then
    CLIENT_ID=11 # Fallback to standard seed data ID
    echo "Warning: Could not fetch Client ID, defaulting to 11"
fi

# 3. Clean up any previous run data
# Delete phases first (foreign key constraint), then project
echo "--- Cleaning up existing project 'WH-RENO-2024' ---"
idempiere_query "DELETE FROM c_projectphase WHERE c_project_id IN (SELECT c_project_id FROM c_project WHERE value='WH-RENO-2024' AND ad_client_id=$CLIENT_ID)" 2>/dev/null || true
idempiere_query "DELETE FROM c_project WHERE value='WH-RENO-2024' AND ad_client_id=$CLIENT_ID" 2>/dev/null || true

# 4. Record initial project count for anti-gaming baseline
INITIAL_PROJECT_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_project WHERE ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")
echo "$INITIAL_PROJECT_COUNT" > /tmp/initial_project_count.txt
echo "Initial project count: $INITIAL_PROJECT_COUNT"

# 5. Ensure Firefox is running and iDempiere is loaded
echo "--- Ensuring iDempiere is ready ---"
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox https://localhost:8443/webui/ &"
    sleep 15
fi

# Navigate to dashboard to ensure we start from a clean state
ensure_idempiere_open ""

# Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="