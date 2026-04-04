#!/bin/bash
set -e
echo "=== Setting up WFS-T Insert Feature task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure GeoServer is running and healthy
verify_geoserver_ready 120 || {
    echo "ERROR: GeoServer not ready, attempting restart..."
    cd /home/ga/geoserver && docker-compose restart gs-app
    sleep 30
    verify_geoserver_ready 120 || { echo "FATAL: GeoServer not responding"; exit 1; }
}

# Ensure WFS service level is COMPLETE (supports transactions)
echo "Ensuring WFS-T is enabled..."
curl -s -u "$GS_AUTH" -X PUT "${GS_URL}/rest/services/wfs/settings" \
    -H "Content-Type: application/json" \
    -d '{"wfs":{"serviceLevel":"COMPLETE"}}' 2>/dev/null
echo "WFS service level set to COMPLETE"

# Ensure no pre-existing test feature (clean state)
echo "Cleaning up any existing 'Nova Cartografia' features..."
postgis_query "DELETE FROM ne_populated_places WHERE name = 'Nova Cartografia';" 2>/dev/null || true

# Record initial feature count
INITIAL_COUNT=$(postgis_query "SELECT count(*) FROM ne_populated_places;" 2>/dev/null | tr -d '[:space:]')
echo "$INITIAL_COUNT" > /tmp/initial_feature_count.txt
echo "Initial feature count: $INITIAL_COUNT"

# Clean up any previous task artifacts
rm -f /home/ga/wfst_insert.xml /home/ga/wfst_response.xml 2>/dev/null || true

# Ensure Firefox is running with GeoServer page
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/geoserver/web/' &" 2>/dev/null
    sleep 5
fi

# Wait for Firefox window
wait_for_window "firefox\|mozilla\|geoserver" 30 || {
    echo "WARNING: Firefox window not detected"
}

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
focus_firefox

# Record namespace URI for internal reference (hidden from agent)
NS_URI=$(curl -s -u "$GS_AUTH" "${GS_URL}/rest/namespaces/ne.json" 2>/dev/null)
echo "$NS_URI" > /tmp/ne_namespace_info.txt

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

# Generate integrity nonce
generate_result_nonce

echo "=== Task setup complete ==="