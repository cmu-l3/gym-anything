#!/bin/bash
set -e
echo "=== Setting up create_user_role task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# -----------------------------------------------------------------------------
# 1. Clean up previous task artifacts
# -----------------------------------------------------------------------------
echo "--- Cleaning up any previous 'Emily Clark' user ---"
# We must delete roles first due to foreign key constraints
idempiere_query "
DELETE FROM ad_user_roles 
WHERE ad_user_id IN (
    SELECT ad_user_id FROM ad_user WHERE name='Emily Clark' AND ad_client_id=11
);" 2>/dev/null || true

idempiere_query "
DELETE FROM ad_user WHERE name='Emily Clark' AND ad_client_id=11;" 2>/dev/null || true

# -----------------------------------------------------------------------------
# 2. Record initial state
# -----------------------------------------------------------------------------
INITIAL_USER_COUNT=$(idempiere_query "SELECT COUNT(*) FROM ad_user WHERE name='Emily Clark' AND ad_client_id=11" 2>/dev/null || echo "0")
echo "$INITIAL_USER_COUNT" > /tmp/initial_emily_count.txt
echo "Initial 'Emily Clark' user count: $INITIAL_USER_COUNT"

# Verify the required role exists in the database
ROLE_CHECK=$(idempiere_query "SELECT COUNT(*) FROM ad_role WHERE name='GardenWorld Admin' AND ad_client_id=11" 2>/dev/null || echo "0")
if [ "$ROLE_CHECK" -eq 0 ]; then
    echo "WARNING: 'GardenWorld Admin' role not found via exact match. Listing available roles:"
    idempiere_query "SELECT name FROM ad_role WHERE ad_client_id=11 AND isactive='Y' LIMIT 10" 2>/dev/null || true
fi

# -----------------------------------------------------------------------------
# 3. Prepare Application
# -----------------------------------------------------------------------------
echo "--- Ensuring iDempiere is accessible ---"

# Check if Firefox is running
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "Firefox not running, starting it..."
    su - ga -c "DISPLAY=:1 firefox https://localhost:8443/webui/ &"
    sleep 15
fi

# Ensure correct window focus
FF_WIN=$(DISPLAY=:1 xdotool search --class Firefox 2>/dev/null | head -1)
if [ -n "$FF_WIN" ]; then
    DISPLAY=:1 xdotool windowfocus --sync "$FF_WIN" 2>/dev/null || true
    DISPLAY=:1 xdotool windowactivate --sync "$FF_WIN" 2>/dev/null || true
    sleep 1
fi
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Navigate to iDempiere dashboard (handles ZK leave-page dialog automatically)
ensure_idempiere_open ""
sleep 2

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="