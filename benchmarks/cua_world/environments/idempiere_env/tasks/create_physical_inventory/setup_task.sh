#!/bin/bash
set -e
echo "=== Setting up create_physical_inventory task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Record initial count of M_Inventory records
# This establishes a baseline to detect if a new record is actually created
CLIENT_ID=$(get_gardenworld_client_id)
# Default to 11 (GardenWorld) if utility fails
CLIENT_ID=${CLIENT_ID:-11}

INITIAL_COUNT=$(idempiere_query "SELECT COUNT(*) FROM m_inventory WHERE ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_inventory_count.txt
echo "Initial inventory count: $INITIAL_COUNT"

# 3. Clean up any previous attempts with the specific description to avoid confusion
# (Optional but good practice for repeatability)
idempiere_query "UPDATE m_inventory SET isactive='N', description=description||'_OLD' WHERE description='Year-End Count Q4 2024' AND ad_client_id=$CLIENT_ID" 2>/dev/null || true

# 4. Ensure Firefox is running and iDempiere is loaded
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox https://localhost:8443/webui/ &"
    # Wait for Firefox
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "firefox"; then
            break
        fi
        sleep 1
    done
fi

# 5. Navigate to Dashboard to ensure clean state
# This handles the ZK "Leave Page?" dialog if it appears
ensure_idempiere_open ""
sleep 2

# 6. Maximize window and focus
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="