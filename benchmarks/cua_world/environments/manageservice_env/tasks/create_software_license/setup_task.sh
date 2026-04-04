#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up create_software_license task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure SDP is running (waits for install if needed)
ensure_sdp_running

# Record initial software license count (Anti-gaming)
# We check SoftwareLicense table or broader ComponentDefinition table
INITIAL_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM softwarelicense;" 2>/dev/null || echo "0")
if [ -z "$INITIAL_COUNT" ] || [ "$INITIAL_COUNT" = "0" ]; then
    # Fallback for some SDP versions where structure might differ slightly
    INITIAL_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM componentdefinition WHERE ci_type LIKE '%Software%' OR ci_type LIKE '%License%';" 2>/dev/null || echo "0")
fi
echo "$INITIAL_COUNT" > /tmp/initial_license_count.txt
echo "Initial license count: $INITIAL_COUNT"

# Ensure Firefox is open and on the login page
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Login.do"

# Wait for window to be ready
sleep 5

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="