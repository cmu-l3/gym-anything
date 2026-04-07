#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Flow Property Conversion task ==="

# 1. Clean up previous results
rm -f /tmp/task_result.json 2>/dev/null || true
RESULTS_DIR="/home/ga/LCA_Results"
mkdir -p "$RESULTS_DIR"
chown ga:ga "$RESULTS_DIR"
rm -f "$RESULTS_DIR/biomass_inventory.csv" 2>/dev/null || true

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Ensure OpenLCA is running
echo "Launching OpenLCA..."
launch_openlca 180

# 4. Maximize window
sleep 2
WID=$(get_openlca_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="