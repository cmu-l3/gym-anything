#!/bin/bash
echo "=== Setting up modify_nose_cone task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Ensure the rocket file exists
if [ ! -f "$ROCKETS_DIR/tube_fin_rocket.ork" ]; then
    echo "Source rocket not found, copying from workspace..."
    cp /workspace/data/rockets/tube_fin_rocket.ork "$ROCKETS_DIR/" 2>/dev/null || true
fi

# Record initial state
INITIAL_MD5=$(file_md5 "$ROCKETS_DIR/tube_fin_rocket.ork")
echo "$INITIAL_MD5" > /tmp/initial_nosecone_md5.txt

# Remove previous output
rm -f "$ROCKETS_DIR/modified_nosecone_rocket.ork" 2>/dev/null || true

# Kill any running OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the tube fin rocket
launch_openrocket "$ROCKETS_DIR/tube_fin_rocket.ork"
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
