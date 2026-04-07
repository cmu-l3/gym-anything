#!/bin/bash
set -e
echo "=== Setting up Configure Request Metadata task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Clean up any existing records with these names to ensure a clean state
# We rename them to avoid unique constraint violations if the agent tries to create them again
# and deactivate them so they don't show up in valid queries.
echo "--- Cleaning up previous test data ---"
CLIENT_ID=$(get_gardenworld_client_id)
# Default to 11 if query fails
CLIENT_ID=${CLIENT_ID:-11}

TIMESTAMP=$(date +%s)

# Helper function to soft-delete/rename existing records
cleanup_record() {
    local table=$1
    local name=$2
    echo "  Cleaning up '$name' from $table..."
    idempiere_query "UPDATE $table SET isactive='N', name=name || '_OLD_$TIMESTAMP' WHERE name='$name' AND ad_client_id=$CLIENT_ID" 2>/dev/null || true
}

cleanup_record "r_requesttype" "Design Consultation"
cleanup_record "r_category" "Plant Selection"
cleanup_record "r_group" "Design Team"
cleanup_record "r_resolution" "Proposal Accepted"

# 3. Ensure iDempiere is running and Firefox is open
echo "--- Ensuring iDempiere is ready ---"
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "  Firefox not running, launching..."
    su - ga -c "DISPLAY=:1 firefox https://localhost:8443/webui/ &"
    sleep 15
else
    echo "  Firefox is running."
fi

# 4. Navigate to Dashboard to ensure clean UI state
ensure_idempiere_open ""

# 5. Maximize window for visibility
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="