#!/bin/bash
echo "=== Setting up configure_wms_settings task ==="

source /workspace/scripts/task_utils.sh

# Record initial WMS settings
WMS_DATA=$(gs_rest_get "services/wms/settings.json")
echo "$WMS_DATA" > /tmp/initial_wms_settings.json
echo "Initial WMS settings recorded"

# Extract current values
INITIAL_MAX_MEMORY=$(echo "$WMS_DATA" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('wms',{}).get('maxRequestMemory',''))" 2>/dev/null || echo "unknown")
INITIAL_MAX_TIME=$(echo "$WMS_DATA" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('wms',{}).get('maxRenderingTime',''))" 2>/dev/null || echo "unknown")
INITIAL_WATERMARK=$(echo "$WMS_DATA" | python3 -c "import sys,json; d=json.load(sys.stdin); wm=d.get('wms',{}).get('watermark',{}); print(str(wm.get('enabled', False)).lower())" 2>/dev/null || echo "unknown")

echo "Initial maxRequestMemory: $INITIAL_MAX_MEMORY"
echo "Initial maxRenderingTime: $INITIAL_MAX_TIME"
echo "Initial watermark enabled: $INITIAL_WATERMARK"

echo "$INITIAL_MAX_MEMORY" > /tmp/initial_max_memory
echo "$INITIAL_MAX_TIME" > /tmp/initial_max_time
echo "$INITIAL_WATERMARK" > /tmp/initial_watermark

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

echo "=== configure_wms_settings task setup complete ==="
