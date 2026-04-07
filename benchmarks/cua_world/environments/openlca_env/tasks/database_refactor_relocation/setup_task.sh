#!/bin/bash
set -e

# Source utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Database Refactor Relocation task ==="

# 1. Clean up previous state
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /home/ga/LCA_Results/refactor_log.txt 2>/dev/null || true

# 2. Prepare Directories
mkdir -p "/home/ga/LCA_Results"
mkdir -p "/home/ga/LCA_Imports"
chown -R ga:ga "/home/ga/LCA_Results" "/home/ga/LCA_Imports"

# 3. Ensure USLCI database zip is available for import
USLCI_ZIP="/home/ga/LCA_Imports/uslci_database.zip"
if [ ! -f "$USLCI_ZIP" ]; then
    echo "Copying USLCI database to imports..."
    if [ -f "/opt/openlca_data/uslci_database.zip" ]; then
        cp /opt/openlca_data/uslci_database.zip "$USLCI_ZIP"
        chown ga:ga "$USLCI_ZIP"
    else
        echo "ERROR: USLCI database source not found in /opt/openlca_data!"
        # We don't exit here to allow the agent to potentially download it if net is enabled, 
        # though strictly the environment should have it.
    fi
fi

# 4. Record Task Start Time
date +%s > /tmp/task_start_time.txt

# 5. Launch OpenLCA
# We launch it empty so the agent must perform the import as per description
echo "Launching OpenLCA..."
launch_openlca 180

# 6. Maximize Window
WID=$(get_openlca_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# 7. Take Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="