#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Material Impact Claim Verification task ==="

# ============================================================
# 1. Clean up previous state
# ============================================================
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /home/ga/LCA_Results/claim_verification.txt 2>/dev/null || true

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Ensure results directory exists
RESULTS_DIR="/home/ga/LCA_Results"
mkdir -p "$RESULTS_DIR"
chown ga:ga "$RESULTS_DIR"

# ============================================================
# 2. Prepare Data (Ensure Zips are available)
# ============================================================
# The task requires the agent to import these, so we just make sure the files exist
USLCI_ZIP="/home/ga/LCA_Imports/uslci_database.zip"
LCIA_ZIP="/home/ga/LCA_Imports/lcia_methods.zip"

mkdir -p "/home/ga/LCA_Imports"
chown ga:ga "/home/ga/LCA_Imports"

# Ensure USLCI zip is present
if [ ! -f "$USLCI_ZIP" ] && [ -f "/opt/openlca_data/uslci_database.zip" ]; then
    cp /opt/openlca_data/uslci_database.zip "$USLCI_ZIP"
    chown ga:ga "$USLCI_ZIP"
fi

# Ensure LCIA zip is present
if [ ! -f "$LCIA_ZIP" ] && [ -f "/opt/openlca_data/lcia_methods.zip" ]; then
    cp /opt/openlca_data/lcia_methods.zip "$LCIA_ZIP"
    chown ga:ga "$LCIA_ZIP"
fi

echo "Data readiness:"
ls -lh "$USLCI_ZIP" "$LCIA_ZIP" 2>/dev/null || echo "WARNING: Data files missing"

# ============================================================
# 3. Launch OpenLCA
# ============================================================
echo "Launching OpenLCA..."
launch_openlca 180

# Maximize window
sleep 5
WID=$(get_openlca_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup complete ==="