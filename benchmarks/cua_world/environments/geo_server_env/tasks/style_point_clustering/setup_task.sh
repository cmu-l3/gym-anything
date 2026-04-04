#!/bin/bash
echo "=== Setting up style_point_clustering task ==="

source /workspace/scripts/task_utils.sh

# 1. Record Initial State
# Check if the layer exists
LAYER_CHECK=$(gs_rest_status "layers/ne:ne_populated_places.json")
if [ "$LAYER_CHECK" != "200" ]; then
    echo "CRITICAL: ne_populated_places layer not found. Setup may fail."
fi

# Record the current default style of ne_populated_places
LAYER_INFO=$(gs_rest_get "layers/ne:ne_populated_places.json")
INITIAL_STYLE=$(echo "$LAYER_INFO" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('layer',{}).get('defaultStyle',{}).get('name',''))" 2>/dev/null || echo "unknown")
echo "$INITIAL_STYLE" > /tmp/initial_default_style.txt
echo "Initial default style: $INITIAL_STYLE"

# Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Setup Firefox
# Ensure Firefox is running and logged in
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/geoserver/web/' > /dev/null 2>&1 &"
    sleep 5
fi

# Wait for window
wait_for_window "firefox\|mozilla" 30

# Ensure logged in to GeoServer
ensure_logged_in

# Focus Firefox
focus_firefox

# 3. Snapshot logs for anti-gaming (GUI interaction check)
snapshot_access_log

# 4. Take initial screenshot
take_screenshot /tmp/task_start.png

# 5. Generate result integrity nonce
generate_result_nonce

echo "=== Task setup complete ==="