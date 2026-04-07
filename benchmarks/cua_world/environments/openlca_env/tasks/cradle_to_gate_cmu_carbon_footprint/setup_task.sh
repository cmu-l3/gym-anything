#!/bin/bash
# Setup script for Cradle-to-Gate CMU Carbon Footprint task

source /workspace/scripts/task_utils.sh

echo "=== Setting up CMU Carbon Footprint task ==="

# 1. Clean stale outputs BEFORE recording timestamp
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/task_start_screenshot.png 2>/dev/null || true
rm -f /tmp/task_end_screenshot.png 2>/dev/null || true
rm -f /home/ga/LCA_Results/cmu_footprint.csv 2>/dev/null || true

# 2. Record start timestamp (used by export_result.sh for anti-gaming)
date +%s > /tmp/task_start_timestamp

# 3. Ensure directories exist
mkdir -p /home/ga/LCA_Imports
mkdir -p /home/ga/LCA_Results
chown -R ga:ga /home/ga/LCA_Imports /home/ga/LCA_Results

# 4. Ensure LCIA methods file is available for the agent to import
# (This task does NOT require USLCI — agent builds everything from scratch)
if [ ! -f "/home/ga/LCA_Imports/lcia_methods.zip" ]; then
    if [ -f "/opt/openlca_data/lcia_methods.zip" ]; then
        cp /opt/openlca_data/lcia_methods.zip /home/ga/LCA_Imports/
        chown ga:ga /home/ga/LCA_Imports/lcia_methods.zip
        echo "LCIA methods staged."
    else
        echo "WARNING: LCIA methods source not found at /opt/openlca_data/"
    fi
fi

# 5. Record initial database count (to detect if agent creates one)
INITIAL_DB_COUNT=$(count_openlca_databases 2>/dev/null || echo "0")
echo "$INITIAL_DB_COUNT" > /tmp/initial_db_count

# 6. Close any interfering windows (e.g. Jurism from cached pre_start state)
pkill -f "jurism\|zotero" 2>/dev/null || true
DISPLAY=:1 wmctrl -c "Firefox" 2>/dev/null || true
sleep 1

# 7. Launch OpenLCA
echo "Launching OpenLCA..."
launch_openlca 180

# 8. Maximize window and focus
sleep 2
WID=$(get_openlca_window_id 2>/dev/null || echo "")
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID" 2>/dev/null || true
    echo "OpenLCA window maximized."
fi

# 9. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
