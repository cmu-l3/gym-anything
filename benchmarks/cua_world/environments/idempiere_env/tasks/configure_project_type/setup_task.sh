#!/bin/bash
set -e
echo "=== Setting up configure_project_type task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Cleanup: Remove any existing Project Type with this name to ensure a clean start
# We need to find the ID first to delete phases, then the header
echo "--- Cleaning up previous attempts ---"
CLIENT_ID=$(get_gardenworld_client_id)
# Default to 11 if query fails
CLIENT_ID=${CLIENT_ID:-11}

PROJECT_TYPE_ID=$(idempiere_query "SELECT c_projecttype_id FROM c_projecttype WHERE name='Winter Garden Prep' AND ad_client_id=$CLIENT_ID" 2>/dev/null || echo "")

if [ -n "$PROJECT_TYPE_ID" ]; then
    echo "  Found existing project type ID: $PROJECT_TYPE_ID. Removing..."
    # Delete phases first (child records)
    idempiere_query "DELETE FROM c_phase WHERE c_projecttype_id=$PROJECT_TYPE_ID" 2>/dev/null || true
    # Delete header
    idempiere_query "DELETE FROM c_projecttype WHERE c_projecttype_id=$PROJECT_TYPE_ID" 2>/dev/null || true
    echo "  Cleanup complete."
else
    echo "  No existing project type found. Clean state confirmed."
fi

# 3. Record initial count (should be 0 for this specific name, but good for tracking total)
INITIAL_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_projecttype WHERE ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_count.txt

# 4. Ensure Firefox is running and navigate to iDempiere
echo "--- Checking Firefox state ---"
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "  Firefox not running, launching..."
    su - ga -c "DISPLAY=:1 firefox https://localhost:8443/webui/ &"
    # Wait for startup
    sleep 15
fi

# 5. Focus and maximize window
echo "--- Preparing Window ---"
# Navigate to dashboard/reset state
navigate_to_dashboard

# Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured."

echo "=== Setup complete ==="