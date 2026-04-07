#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Water Energy Demand Task ==="

# 1. Clean up previous run artifacts
rm -f /tmp/task_result.json 2>/dev/null || true
rm -rf /home/ga/LCA_Results/* 2>/dev/null || true
mkdir -p /home/ga/LCA_Results
chown ga:ga /home/ga/LCA_Results

# 2. Ensure Import Files are ready
# The environment installation script puts them in /opt/openlca_data/
# We copy them to the user's import directory for easy access
mkdir -p /home/ga/LCA_Imports
if [ -f "/opt/openlca_data/uslci_database.zip" ]; then
    cp /opt/openlca_data/uslci_database.zip /home/ga/LCA_Imports/
fi
if [ -f "/opt/openlca_data/lcia_methods.zip" ]; then
    cp /opt/openlca_data/lcia_methods.zip /home/ga/LCA_Imports/
fi
chown -R ga:ga /home/ga/LCA_Imports

# 3. Record Initial State
# Count databases (should be 0 or low if env is fresh)
INITIAL_DB_COUNT=$(count_openlca_databases)
echo "$INITIAL_DB_COUNT" > /tmp/initial_db_count

# Record start time for anti-gaming (file modification checks)
date +%s > /tmp/task_start_time.txt

# 4. Launch OpenLCA
# We launch it so the agent lands in the application, ready to work.
echo "Launching OpenLCA..."
launch_openlca 180

# 5. UI Setup
# Maximize window
WID=$(get_openlca_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# 6. Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="