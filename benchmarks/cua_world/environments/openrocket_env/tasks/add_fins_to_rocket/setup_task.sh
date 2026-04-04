#!/bin/bash
echo "=== Setting up add_fins_to_rocket task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Ensure the source rocket file exists
if [ ! -f "$ROCKETS_DIR/simple_model_rocket.ork" ]; then
    echo "ERROR: simple_model_rocket.ork not found!"
    # Try copying from workspace data
    cp /workspace/data/rockets/simple_model_rocket.ork "$ROCKETS_DIR/" 2>/dev/null || true
fi

# Record initial state for delta verification
INITIAL_MD5=$(file_md5 "$ROCKETS_DIR/simple_model_rocket.ork")
echo "$INITIAL_MD5" > /tmp/initial_rocket_md5.txt

# Remove previous output file if exists
rm -f "$ROCKETS_DIR/modified_rocket_with_fins.ork" 2>/dev/null || true

# Kill any running OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the simple model rocket
launch_openrocket "$ROCKETS_DIR/simple_model_rocket.ork"
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
