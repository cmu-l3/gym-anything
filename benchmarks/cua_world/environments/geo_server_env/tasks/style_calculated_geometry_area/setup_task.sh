#!/bin/bash
echo "=== Setting up style_calculated_geometry_area task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Record initial style count in 'ne' workspace
INITIAL_COUNT=$(gs_rest_get "workspaces/ne/styles.json" | python3 -c "import sys,json; d=json.load(sys.stdin); styles=d.get('styles',{}).get('style',[]); print(len(styles) if isinstance(styles,list) else (1 if styles else 0))" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_style_count
echo "Initial 'ne' workspace style count: $INITIAL_COUNT"

# Ensure Firefox is running and logged in
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080/geoserver/web/' &
    sleep 5
fi
wait_for_window "firefox\|mozilla" 30
ensure_logged_in

# Focus Firefox
focus_firefox
DISPLAY=:1 xdotool mousemove 960 540 click 1
sleep 1

# Generate integrity nonce
NONCE=$(generate_result_nonce)
echo "Result nonce: $NONCE"

# Snapshot access log for GUI interaction detection
snapshot_access_log

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup complete ==="