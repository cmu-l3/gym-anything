#!/bin/bash
# Setup script for Soybean Allocation Configuration task
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Soybean Allocation Task ==="

# 1. Clean up previous artifacts
rm -f /tmp/task_result.json 2>/dev/null || true
RESULTS_DIR="/home/ga/LCA_Results"
mkdir -p "$RESULTS_DIR"
chown ga:ga "$RESULTS_DIR"
# Remove specific result file if it exists to ensure fresh creation
rm -f "$RESULTS_DIR/soybean_allocation.csv" 2>/dev/null || true

# 2. Record Task Start Time (Anti-gaming)
date +%s > /tmp/task_start_timestamp

# 3. Ensure Data Sources are available
# USLCI Database
USLCI_ZIP="/home/ga/LCA_Imports/uslci_database.zip"
if [ ! -f "$USLCI_ZIP" ] && [ -f "/opt/openlca_data/uslci_database.zip" ]; then
    mkdir -p "/home/ga/LCA_Imports"
    cp /opt/openlca_data/uslci_database.zip "$USLCI_ZIP"
    chown ga:ga "$USLCI_ZIP"
fi

# LCIA Methods
LCIA_ZIP="/home/ga/LCA_Imports/lcia_methods.zip"
if [ ! -f "$LCIA_ZIP" ] && [ -f "/opt/openlca_data/lcia_methods.zip" ]; then
    mkdir -p "/home/ga/LCA_Imports"
    cp /opt/openlca_data/lcia_methods.zip "$LCIA_ZIP"
    chown ga:ga "$LCIA_ZIP"
fi

# 4. Launch OpenLCA
echo "Launching OpenLCA..."
launch_openlca 180

# 5. Window Management
sleep 5
WID=$(get_openlca_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# 6. Initial Screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="