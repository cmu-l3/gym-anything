#!/bin/bash
echo "=== Setting up retrieve_wfs_filtered_features task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is clean
mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/europe_countries.geojson
rm -f /home/ga/Documents/europe_report.txt

# Ensure GeoServer is running and accessible
echo "Waiting for GeoServer..."
if ! verify_geoserver_ready 60; then
    echo "Restarting GeoServer..."
    docker restart gs-app
    verify_geoserver_ready 120
fi

# Ensure Firefox is open to the GeoServer web admin
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/geoserver/web/' > /dev/null 2>&1 &"
    sleep 5
fi

# Maximize Firefox
focus_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

# Record ground truth (hidden from agent)
# We count how many Europe countries are actually in the DB to verify the agent's result later
echo "Calculating ground truth..."
GROUND_TRUTH_COUNT=$(postgis_query "SELECT count(*) FROM ne_countries WHERE continent='Europe'" 2>/dev/null || echo "0")
echo "$GROUND_TRUTH_COUNT" > /tmp/ground_truth_count.txt
echo "Ground truth count (Europe): $GROUND_TRUTH_COUNT"

echo "=== Task setup complete ==="