#!/bin/bash
set -e
echo "=== Setting up Configure Video Wall Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Refresh authentication token to ensure API is ready
TOKEN=$(refresh_nx_token)
echo "Auth token refreshed"

# 1. Clean up previous state (Idempotency)
echo "Cleaning up previous task artifacts..."

# Delete existing Video Wall if it exists
nx_api_get "/rest/v1/videoWalls" | python3 -c "
import sys, json
try:
    walls = json.load(sys.stdin)
    for w in walls:
        if 'distribution hub soc' in w.get('name','').lower():
            print(w['id'])
except:
    pass
" 2>/dev/null | while read vw_id; do
    echo "Removing pre-existing video wall: $vw_id"
    nx_api_delete "/rest/v1/videoWalls/${vw_id}"
done

# Delete existing SOC layouts
nx_api_get "/rest/v1/layouts" | python3 -c "
import sys, json
try:
    layouts = json.load(sys.stdin)
    for l in layouts:
        if l.get('name','').startswith('SOC -'):
            print(l['id'])
except:
    pass
" 2>/dev/null | while read layout_id; do
    echo "Removing pre-existing SOC layout: $layout_id"
    nx_api_delete "/rest/v1/layouts/${layout_id}"
done

# Remove report file
rm -f /home/ga/video_wall_report.txt

# 2. Record Initial State for Verification
INITIAL_VW_COUNT=$(nx_api_get "/rest/v1/videoWalls" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
echo "$INITIAL_VW_COUNT" > /tmp/initial_vw_count.txt

INITIAL_LAYOUT_COUNT=$(count_layouts)
echo "$INITIAL_LAYOUT_COUNT" > /tmp/initial_layout_count.txt

# 3. Prepare Environment
# Ensure Firefox is open to the API documentation or Web Admin to give context
ensure_firefox_running "https://localhost:7001/static/index.html#/settings/systems"
sleep 5
dismiss_ssl_warning
maximize_firefox

# 4. Verify Cameras exist (Prerequisite)
CAM_COUNT=$(count_cameras)
if [ "$CAM_COUNT" -lt 3 ]; then
    echo "WARNING: Less than 3 cameras found ($CAM_COUNT). Task requires 3."
    # Attempt to restart testcamera if missing
    /workspace/scripts/setup_nx_witness.sh > /dev/null 2>&1 &
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Initial Video Walls: $INITIAL_VW_COUNT"
echo "Initial Layouts: $INITIAL_LAYOUT_COUNT"