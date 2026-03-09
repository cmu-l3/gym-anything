#!/bin/bash
echo "=== Setting up run_flight_simulation task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Ensure the rocket file exists
if [ ! -f "$ROCKETS_DIR/EPFL_BellaLui_2020.ork" ]; then
    echo "Source rocket not found, copying from workspace..."
    cp /workspace/data/rockets/EPFL_BellaLui_2020.ork "$ROCKETS_DIR/" 2>/dev/null || true
fi

# Create exports directory
mkdir -p "$EXPORTS_DIR"
chown ga:ga "$EXPORTS_DIR"

# Record initial state
ls "$EXPORTS_DIR"/*.csv 2>/dev/null | wc -l > /tmp/initial_csv_count.txt

# Remove previous output
rm -f "$EXPORTS_DIR/bellalui_simulation.csv" 2>/dev/null || true

# Kill any running OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the BellaLui rocket
launch_openrocket "$ROCKETS_DIR/EPFL_BellaLui_2020.ork"
sleep 3

# Wait for window
wait_for_openrocket 60

# Focus and maximize
sleep 3
focus_openrocket_window
sleep 2

# Dismiss any startup dialogs
dismiss_dialogs 2

echo "=== Task setup complete ==="
