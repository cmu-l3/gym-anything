#!/bin/bash
# Setup script for Custom LCIA Water Scarcity task
# Pre-task hook: runs BEFORE the agent starts

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type launch_openlca &>/dev/null; then
    launch_openlca() { su - ga -c "DISPLAY=:1 /home/ga/launch_openlca.sh" & sleep 20; }
fi

echo "=== Setting up Custom LCIA Water Scarcity task ==="

# Clean up any previous state
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/water_scarcity_result.json 2>/dev/null || true

# Ensure results directory exists
RESULTS_DIR="/home/ga/LCA_Results"
mkdir -p "$RESULTS_DIR"
chown ga:ga "$RESULTS_DIR"

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

# Ensure USLCI zip is available
USLCI_ZIP="/home/ga/LCA_Imports/uslci_database.zip"
mkdir -p "$(dirname "$USLCI_ZIP")"
if [ ! -f "$USLCI_ZIP" ]; then
    if [ -f "/opt/openlca_data/uslci_database.zip" ]; then
        cp /opt/openlca_data/uslci_database.zip "$USLCI_ZIP"
        echo "Copied USLCI zip from /opt/openlca_data/"
    else
        echo "WARNING: USLCI database zip not found!"
    fi
fi
chown -R ga:ga "/home/ga/LCA_Imports"

# Record initial method count to detect new creation
# We need to find the active database first, but since the agent might
# create a new one or import, we just record counts for any existing DBs.
DB_DIR="/home/ga/openLCA-data-1.4/databases"
echo "Recording initial state of databases..."
mkdir -p /tmp/initial_counts
for db_path in "$DB_DIR"/*/; do
    if [ -d "$db_path" ]; then
        db_name=$(basename "$db_path")
        count=$(derby_count "$db_path" "IMPACT_METHODS" 2>/dev/null || echo "0")
        echo "$db_name:$count" >> /tmp/initial_counts/method_counts.txt
    fi
done

# Launch OpenLCA
echo "Launching OpenLCA..."
launch_openlca 180

# Maximize window
sleep 2
WID=$(get_openlca_window_id 2>/dev/null || echo "")
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID" 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png
echo "Initial screenshot saved"

echo "=== Setup complete ==="