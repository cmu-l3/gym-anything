#!/bin/bash
echo "=== Setting up optimize_layer_delivery task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ==============================================================================
# 1. Reset Layer State
# ==============================================================================
# Ensure ne:ne_countries exists and has default settings (no caching, no attribution)
echo "Resetting configuration for ne:ne_countries..."

# Reset HTTP caching (disable it via REST)
# Note: GeoServer REST API for 'layers' endpoint handles publishing settings
curl -u "$GS_AUTH" -X PUT -H "Content-Type: application/json" \
  "${GS_REST}/layers/ne:ne_countries.json" \
  -d '{
    "layer": {
      "attribution": {
        "title": "",
        "logoWidth": 0,
        "logoHeight": 0
      },
      "resource": {
        "href": "'"${GS_REST}"'/workspaces/ne/datastores/postgis_ne/featuretypes/ne_countries.json"
      }
    }
  }' 2>/dev/null

# We also need to check if we can unset the HTTP cache headers specifically.
# Usually, if not set, they default to global settings or disabled.
# This specific setting might be obscure in REST, but clearing the attribution is key.

# ==============================================================================
# 2. Setup Dummy Logo
# ==============================================================================
# Create a dummy logo file so the URL resolves (avoids 404s during verification, though not strictly required)
# The webapps root is usually /usr/local/tomcat/webapps/geoserver
if docker exec gs-app test -d /usr/local/tomcat/webapps/geoserver; then
    docker exec gs-app bash -c "convert -size 88x31 xc:white /usr/local/tomcat/webapps/geoserver/ne_logo.png" 2>/dev/null || true
    docker exec gs-app bash -c "chown tomcat:tomcat /usr/local/tomcat/webapps/geoserver/ne_logo.png" 2>/dev/null || true
fi

# ==============================================================================
# 3. GUI Setup
# ==============================================================================
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

# ==============================================================================
# 4. Anti-Gaming
# ==============================================================================
# Generate integrity nonce
NONCE=$(generate_result_nonce)
echo "Result nonce: $NONCE"

# Snapshot access log for GUI interaction detection
snapshot_access_log

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== optimize_layer_delivery task setup complete ==="