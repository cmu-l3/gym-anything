#!/bin/bash
echo "=== Setting up style_points_external_graphic task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ============================================================
# Clean up previous attempts (if any)
# ============================================================
echo "Cleaning up any previous artifacts..."

# 1. Reset layer style if it was changed
LAYER_DATA=$(gs_rest_get "layers/ne:ne_populated_places.json")
CURRENT_STYLE=$(echo "$LAYER_DATA" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('layer',{}).get('defaultStyle',{}).get('name',''))" 2>/dev/null)

if [ "$CURRENT_STYLE" == "star_marker" ]; then
    echo "Resetting layer style to 'point'..."
    curl -s -u "$GS_AUTH" -X PUT -H "Content-type: application/json" \
        -d '{"layer": {"defaultStyle": {"name": "point"}}}' \
        "${GS_REST}/layers/ne:ne_populated_places"
fi

# 2. Delete style 'star_marker' if exists
STATUS=$(gs_rest_status "styles/star_marker.json")
if [ "$STATUS" == "200" ]; then
    echo "Deleting global style star_marker..."
    curl -s -u "$GS_AUTH" -X DELETE "${GS_REST}/styles/star_marker?recurse=true"
fi
STATUS_WS=$(gs_rest_status "workspaces/ne/styles/star_marker.json")
if [ "$STATUS_WS" == "200" ]; then
    echo "Deleting workspace style ne:star_marker..."
    curl -s -u "$GS_AUTH" -X DELETE "${GS_REST}/workspaces/ne/styles/star_marker?recurse=true"
fi

# 3. Remove star.svg from data directory
docker exec gs-app bash -c "find /opt/geoserver/data_dir -name 'star.svg' -type f -delete"

# ============================================================
# Prepare Environment
# ============================================================

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

# Snapshot access log for GUI interaction detection
snapshot_access_log

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup complete ==="