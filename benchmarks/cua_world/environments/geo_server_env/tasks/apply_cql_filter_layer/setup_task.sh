#!/bin/bash
set -e
echo "=== Setting up apply_cql_filter_layer task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure GeoServer is ready
verify_geoserver_ready 60

# ============================================================
# 1. Reset/Ensure Clean State
# ============================================================
echo "Resetting ne_countries configuration..."
# Clear any existing CQL filter to ensure we start with the full dataset
# We use PUT to the FeatureType endpoint
curl -u "$GS_AUTH" -X PUT "${GS_URL}/rest/workspaces/ne/datastores/postgis_ne/featuretypes/ne_countries.json" \
    -H "Content-Type: application/json" \
    -d '{
        "featureType": {
            "cqlFilter": ""
        }
    }' 2>/dev/null || echo "Warning: Failed to reset CQL filter"

sleep 2

# ============================================================
# 2. Record Initial State (Baseline)
# ============================================================
# Get initial feature count via WFS (should be ~177)
echo "Measuring initial feature count..."
INITIAL_WFS_JSON=$(curl -s "${GS_URL}/ne/ows?service=WFS&version=1.0.0&request=GetFeature&typeName=ne:ne_countries&outputFormat=application/json")
INITIAL_COUNT=$(echo "$INITIAL_WFS_JSON" | python3 -c "import sys, json; print(len(json.load(sys.stdin).get('features', [])))" 2>/dev/null || echo "0")

echo "$INITIAL_COUNT" > /tmp/initial_feature_count.txt
echo "Initial feature count: $INITIAL_COUNT"

# ============================================================
# 3. Prepare Browser
# ============================================================
# Ensure Firefox is running
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/geoserver/web/' &"
    sleep 5
fi

wait_for_window "firefox\|mozilla" 30

# Maximize
focus_firefox

# Login automated helper (optional, but good for setup)
# We let the agent do the login as part of the task usually, but 
# ensuring the window is ready is key.
# Based on task description: "Log in to GeoServer..." -> Agent must login.

# Snapshot access log for GUI interaction detection
snapshot_access_log

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="