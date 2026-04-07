#!/bin/bash
echo "=== Setting up jazz_session_setup task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

SESSION_DIR="/home/ga/Audio/sessions/MyProject"
SNAPSHOT_FILE="$SESSION_DIR/Pre_Show_Template.ardour"

# Ensure clean state (remove any previous snapshot)
rm -f "$SNAPSHOT_FILE" 2>/dev/null || true

# Kill any existing Ardour instances forcefully to start clean
kill_ardour

# Wait before launching
sleep 2

# Launch Ardour with the main default session
launch_ardour_session "$SESSION_DIR/MyProject.ardour"

# Give the UI time to settle
sleep 5

# Capture initial state evidence
echo "Capturing initial state..."
take_screenshot /tmp/task_initial_state.png 2>/dev/null || true

# Verify screenshot was captured
if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo "=== Task setup complete ==="