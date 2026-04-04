#!/bin/bash
echo "=== Setting up design_two_stage_rocket task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Ensure reference rocket file exists
if [ ! -f "$ROCKETS_DIR/NDRT_Rocket_2020.ork" ]; then
    echo "Reference rocket not found, copying from workspace..."
    cp /workspace/data/rockets/NDRT_Rocket_2020.ork "$ROCKETS_DIR/" 2>/dev/null || true
fi

# Record initial state for delta verification
ls "$ROCKETS_DIR"/*.ork 2>/dev/null | wc -l > /tmp/initial_ork_count.txt

# Remove previous output
rm -f "$ROCKETS_DIR/my_two_stage_rocket.ork" 2>/dev/null || true

# Kill any running OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the reference rocket so the agent can see a two-stage design
launch_openrocket "$ROCKETS_DIR/NDRT_Rocket_2020.ork"
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
