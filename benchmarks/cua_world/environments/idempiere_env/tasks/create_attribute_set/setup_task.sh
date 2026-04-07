#!/bin/bash
set -e
echo "=== Setting up create_attribute_set task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Get GardenWorld Client ID
CLIENT_ID=$(get_gardenworld_client_id)
echo "Using Client ID: $CLIENT_ID"

# ---------------------------------------------------------------
# Clean up any pre-existing record to ensure clean state
# ---------------------------------------------------------------
echo "--- Cleaning up pre-existing SER_LOT_TRACK attribute set ---"
EXISTING=$(idempiere_query "SELECT COUNT(*) FROM m_attributeset WHERE value='SER_LOT_TRACK' AND ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")

if [ "$EXISTING" -gt 0 ]; then
    echo "  Deleting existing record..."
    # We use UPDATE to deactivate instead of DELETE to avoid foreign key constraints if it was used elsewhere
    # But for a clean test environment, DELETE is preferred if possible. 
    # Try DELETE, fallback to deactivating/renaming if failed.
    idempiere_query "DELETE FROM m_attributeset WHERE value='SER_LOT_TRACK' AND ad_client_id=$CLIENT_ID" 2>/dev/null || \
    idempiere_query "UPDATE m_attributeset SET value='SER_LOT_TRACK_OLD_' || floor(random()*1000), isactive='N' WHERE value='SER_LOT_TRACK' AND ad_client_id=$CLIENT_ID" 2>/dev/null || true
fi

# Record initial attribute set count
INITIAL_COUNT=$(idempiere_query "SELECT COUNT(*) FROM m_attributeset WHERE ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_attributeset_count.txt
echo "Initial attribute set count: $INITIAL_COUNT"

# ---------------------------------------------------------------
# Ensure Firefox is open and showing iDempiere
# ---------------------------------------------------------------
echo "--- Ensuring iDempiere is accessible ---"

# Check if Firefox is running
if ! pgrep -f "firefox" > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox https://localhost:8443/webui/ &"
    sleep 15
fi

# Wait for Firefox window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iq "firefox\|mozilla"; then
        echo "Firefox window found"
        break
    fi
    sleep 1
done

# Navigate to iDempiere dashboard to ensure clean starting state
ensure_idempiere_open ""
sleep 5

# Focus and maximize Firefox
DISPLAY=:1 wmctrl -xa firefox 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="