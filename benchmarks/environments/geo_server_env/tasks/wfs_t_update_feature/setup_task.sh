#!/bin/bash
echo "=== Setting up wfs_t_update_feature task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure PostGIS is ready and data is loaded
wait_for_postgis 30

# Reset Shanghai population to a known initial value (different from target)
# This prevents 'accidental' passing if the value happened to match
echo "Resetting Shanghai population..."
postgis_query "UPDATE ne_populated_places SET pop_max = 24000000 WHERE name = 'Shanghai';"
INITIAL_VAL=$(postgis_query "SELECT pop_max FROM ne_populated_places WHERE name = 'Shanghai';")
echo "Initial Shanghai population: $INITIAL_VAL"

# Record initial state
echo "$INITIAL_VAL" > /tmp/initial_pop_max.txt

# Remove any previous artifacts
rm -f /home/ga/wfs_update.xml /home/ga/wfs_response.xml

# Ensure GeoServer is running and Firefox is open
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080/geoserver/web/' &
    sleep 5
fi
wait_for_window "firefox\|mozilla" 60

# Maximize Firefox
focus_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="