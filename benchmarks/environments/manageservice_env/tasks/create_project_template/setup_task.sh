#!/bin/bash
# Setup script for create_project_template task
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Create Project Template Task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure ServiceDesk Plus is running (waits for install if needed)
ensure_sdp_running

# Record initial count of templates to detect new creation
# We check both likely tables since SDP schema versions vary
INITIAL_TEMPLATE_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM projectdetails WHERE is_template='true';" 2>/dev/null || echo "0")
if [ "$INITIAL_TEMPLATE_COUNT" = "0" ]; then
    # Fallback to projecttemplate table if projectdetails doesn't have is_template or is empty
    INITIAL_TEMPLATE_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM projecttemplate;" 2>/dev/null || echo "0")
fi
echo "$INITIAL_TEMPLATE_COUNT" > /tmp/initial_template_count.txt

# Launch Firefox to the Projects module or Home
# Note: Project Templates are usually under Admin or Projects tab. 
# We'll start at the Home dashboard to force navigation.
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Login.do"

# Wait for window and maximize
sleep 5
WID=$(xdotool search --onlyvisible --name "Firefox" | head -1)
if [ -n "$WID" ]; then
    xdotool windowactivate "$WID"
    xdotool key F11 2>/dev/null || wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="