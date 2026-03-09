#!/bin/bash
set -e
echo "=== Setting up configure_global_settings task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ==============================================================================
# Reset GeoServer Configuration to Defaults (Ensure Clean State)
# ==============================================================================
echo "Resetting global settings to defaults..."

# 1. Reset Global Settings
# proxyBaseUrl: empty, numDecimals: 8, verbose: false, charset: UTF-8
curl -s -u "$GS_AUTH" -X PUT -H "Content-Type: application/json" -d '{
  "global": {
    "proxyBaseUrl": "",
    "numDecimals": 8,
    "verbose": false,
    "globalServices": true,
    "charset": "UTF-8"
  }
}' "${GS_REST}/settings" > /dev/null

# 2. Reset Logging
# level: DEFAULT_LOGGING
curl -s -u "$GS_AUTH" -X PUT -H "Content-Type: application/json" -d '{
  "logging": {
    "level": "DEFAULT_LOGGING",
    "location": "",
    "stdOutLogging": false
  }
}' "${GS_REST}/logging" > /dev/null

# 3. Reset Contact Information
# minimal default info
curl -s -u "$GS_AUTH" -X PUT -H "Content-Type: application/json" -d '{
  "contact": {
    "contactPerson": "Default Contact",
    "contactOrganization": "Default Organization"
  }
}' "${GS_REST}/settings/contact" > /dev/null

echo "Configuration reset complete."

# ==============================================================================
# Setup Browser and Environment
# ==============================================================================

# Snapshot access log for GUI interaction detection
# (We look for the access log file and save its current line count)
ACCESS_LOG=$(docker exec gs-app bash -c 'ls -t /usr/local/tomcat/logs/localhost_access_log.*.txt 2>/dev/null | head -1' 2>/dev/null || echo "")
if [ -n "$ACCESS_LOG" ]; then
    COUNT=$(docker exec gs-app wc -l < "$ACCESS_LOG" 2>/dev/null || echo "0")
    echo "$COUNT" > /tmp/access_log_start_count
    echo "$ACCESS_LOG" > /tmp/access_log_path
    echo "Access log snapshot: $COUNT lines in $ACCESS_LOG"
else
    echo "0" > /tmp/access_log_start_count
    echo "" > /tmp/access_log_path
    echo "WARNING: Could not locate access log"
fi

# Ensure Firefox is running and logged in
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080/geoserver/web/' &
    sleep 5
fi

wait_for_window "firefox\|mozilla" 30
ensure_logged_in

# Focus Firefox
focus_firefox

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup complete ==="