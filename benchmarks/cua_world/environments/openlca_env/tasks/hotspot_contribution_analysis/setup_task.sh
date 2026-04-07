#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Hotspot Contribution Analysis Task ==="

# 1. Record Task Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 2. Prepare Directories and Data
RESULTS_DIR="/home/ga/LCA_Results"
mkdir -p "$RESULTS_DIR"
chown ga:ga "$RESULTS_DIR"

# Clean up previous results to ensure we detect new files
rm -f "$RESULTS_DIR/hotspot_report.csv"
rm -f "$RESULTS_DIR/hotspot_summary.txt"
rm -f /tmp/task_result.json

# Ensure Import Data is Available
IMPORTS_DIR="/home/ga/LCA_Imports"
mkdir -p "$IMPORTS_DIR"

# Copy USLCI if not present in user dir
if [ ! -f "$IMPORTS_DIR/uslci_database.zip" ]; then
    if [ -f "/opt/openlca_data/uslci_database.zip" ]; then
        cp /opt/openlca_data/uslci_database.zip "$IMPORTS_DIR/"
        echo "Copied USLCI database to imports."
    else
        echo "WARNING: USLCI database source not found!"
    fi
fi

# Copy LCIA methods if not present
if [ ! -f "$IMPORTS_DIR/lcia_methods.zip" ]; then
    if [ -f "/opt/openlca_data/lcia_methods.zip" ]; then
        cp /opt/openlca_data/lcia_methods.zip "$IMPORTS_DIR/"
        echo "Copied LCIA methods to imports."
    fi
fi
chown -R ga:ga "$IMPORTS_DIR"

# 3. Record Initial DB State
# We want to know if the agent actually imports the database
DB_DIR="/home/ga/openLCA-data-1.4/databases"
INITIAL_DB_COUNT=$(count_openlca_databases)
echo "$INITIAL_DB_COUNT" > /tmp/initial_db_count.txt

# 4. Launch OpenLCA
echo "Launching OpenLCA..."
launch_openlca 180

# 5. Ensure Window is Maximized and Focused
WID=$(get_openlca_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# 6. Capture Initial Screenshot
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured."

echo "=== Setup Complete ==="