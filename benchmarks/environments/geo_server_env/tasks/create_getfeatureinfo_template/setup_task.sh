#!/bin/bash
echo "=== Setting up create_getfeatureinfo_template task ==="

source /workspace/scripts/task_utils.sh

# Target file path inside container
TEMPLATE_PATH="/opt/geoserver/data_dir/workspaces/ne/postgis_ne/ne_countries/content.ftl"

# 1. Clean state: Remove any existing template
echo "Ensuring clean state..."
docker exec gs-app rm -f "$TEMPLATE_PATH" 2>/dev/null || true

# 2. Record default GetFeatureInfo response (Baseline)
# Request for a point in France (approx Lat 47, Lon 2)
# BBOX centered around it slightly
echo "Recording baseline GetFeatureInfo response..."
BASELINE_URL="http://localhost:8080/geoserver/ne/wms?SERVICE=WMS&VERSION=1.1.1&REQUEST=GetFeatureInfo&FORMAT=image/png&TRANSPARENT=true&QUERY_LAYERS=ne:ne_countries&LAYERS=ne:ne_countries&STYLES=&INFO_FORMAT=text/html&FEATURE_COUNT=1&X=50&Y=50&SRS=EPSG:4326&WIDTH=101&HEIGHT=101&BBOX=1.0,46.0,3.0,48.0"

BASELINE_RESPONSE=$(curl -s "$BASELINE_URL")
echo "$BASELINE_RESPONSE" > /tmp/baseline_response.txt

# Verify the layer is actually working first
if echo "$BASELINE_RESPONSE" | grep -q "ServiceException"; then
    echo "WARNING: Layer ne_countries might not be working correctly."
    echo "Response: $BASELINE_RESPONSE"
fi

# 3. Ensure Firefox is running and logged in
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

# 4. Record start time
date +%s > /tmp/task_start_time.txt

# 5. Snapshot access log
snapshot_access_log

# 6. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup complete ==="