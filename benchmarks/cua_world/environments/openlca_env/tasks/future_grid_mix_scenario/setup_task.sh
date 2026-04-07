#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Future Grid Mix Scenario ==="

# 1. Cleanup previous run artifacts
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /home/ga/LCA_Results/grid_2035_results.csv 2>/dev/null || true
rm -f /home/ga/LCA_Results/mix_composition.txt 2>/dev/null || true

# 2. Ensure Results Directory exists
mkdir -p /home/ga/LCA_Results
chown ga:ga /home/ga/LCA_Results

# 3. Ensure Import Files are ready (but do NOT import them automatically)
# The agent must demonstrate ability to import.
mkdir -p /home/ga/LCA_Imports
if [ -f "/opt/openlca_data/uslci_database.zip" ]; then
    cp /opt/openlca_data/uslci_database.zip /home/ga/LCA_Imports/
fi
if [ -f "/opt/openlca_data/lcia_methods.zip" ]; then
    cp /opt/openlca_data/lcia_methods.zip /home/ga/LCA_Imports/
fi
chown -R ga:ga /home/ga/LCA_Imports

# 4. Record Initial State
# We count existing databases to detect if agent creates/imports one
INITIAL_DB_COUNT=$(count_openlca_databases)
echo "$INITIAL_DB_COUNT" > /tmp/initial_db_count
date +%s > /tmp/task_start_time

# 5. Launch OpenLCA
echo "Launching OpenLCA..."
launch_openlca 180

# 6. Window Management
WID=$(get_openlca_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz
    focus_window "$WID"
fi

# 7. Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="