#!/bin/bash
set -e
echo "=== Setting up configure_tile_caching task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Clean up potential pre-existing state (idempotency)
echo "Cleaning up any existing WebMercator512 configuration..."

# Remove gridset from layer if present
curl -s -u "$GS_AUTH" -X GET "${GS_REST}/layers/ne:ne_countries.xml" -o /tmp/layer_check.xml 2>/dev/null || true
if grep -q "WebMercator512" /tmp/layer_check.xml; then
    # We can't easily edit XML with curl to remove one gridset without complex sed/xmlstarlet
    # So we reset the layer to a known default state (only EPSG:4326 and EPSG:900913)
    curl -v -u "$GS_AUTH" -X POST -H "Content-Type: text/xml" -d \
    "<layer><enabled>true</enabled><gridSubsets><gridSubset><gridSetName>EPSG:4326</gridSetName></gridSubset><gridSubset><gridSetName>EPSG:900913</gridSetName></gridSubset></gridSubsets></layer>" \
    "${GWC_REST}/layers/ne:ne_countries.xml" 2>/dev/null || echo "Warning: Failed to reset layer config"
fi

# Remove the gridset itself
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "$GS_AUTH" "${GWC_REST}/gridsets/WebMercator512" 2>/dev/null)
if [ "$HTTP_CODE" = "200" ]; then
    curl -s -u "$GS_AUTH" -X DELETE "${GWC_REST}/gridsets/WebMercator512" 2>/dev/null || true
    echo "Removed pre-existing gridset."
fi

# 2. Record initial gridset list (for anti-gaming verification)
curl -s -u "$GS_AUTH" -H "Accept: application/json" "${GWC_REST}/gridsets" > /tmp/initial_gridsets.json
echo "Initial gridsets recorded."

# 3. Ensure Firefox is running and logged in
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/geoserver/web/' &"
    sleep 5
fi

wait_for_window "firefox\|mozilla" 30
ensure_logged_in

# 4. Focus Firefox and maximize
focus_firefox
DISPLAY=:1 xdotool mousemove 960 540 click 1
sleep 1

# 5. Generate result nonce for integrity
NONCE=$(generate_result_nonce)
echo "Result nonce: $NONCE"

# 6. Snapshot access log for GUI interaction detection
snapshot_access_log

# 7. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== configure_tile_caching task setup complete ==="