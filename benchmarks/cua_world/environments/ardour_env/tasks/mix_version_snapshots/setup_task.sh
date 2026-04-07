#!/bin/bash
echo "=== Setting up mix_version_snapshots task ==="

source /workspace/scripts/task_utils.sh

# Kill any existing Ardour instances to ensure a clean start
kill_ardour

SESSION_DIR="/home/ga/Audio/sessions/MyProject"
SESSION_FILE="$SESSION_DIR/MyProject.ardour"

# Verify the session directory exists
if [ ! -d "$SESSION_DIR" ]; then
    echo "ERROR: Session directory not found at $SESSION_DIR"
    exit 1
fi

# Clean up any existing snapshots from previous runs to prevent gaming
echo "Cleaning up any old snapshots..."
find "$SESSION_DIR" -maxdepth 1 -name "*.ardour" ! -name "MyProject.ardour" -delete

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp
echo "Task start time recorded."

# Launch Ardour with the standard session
echo "Launching Ardour session..."
launch_ardour_session "$SESSION_FILE"
sleep 5

# Ensure main window is focused and maximized
WID=$(DISPLAY=:1 xdotool search --name "MyProject" 2>/dev/null | head -1)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r "MyProject" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot for evidence
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="