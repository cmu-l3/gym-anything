#!/bin/bash
echo "=== Setting up rename_track task ==="

source /workspace/scripts/task_utils.sh

# Kill any existing Ardour instances
kill_ardour

SESSION_DIR="/home/ga/Audio/sessions/MyProject"

# Ensure session exists and the track is named "Audio 1"
if [ -f "$SESSION_DIR/MyProject.ardour" ]; then
    # Reset track name to "Audio 1" if it was renamed
    sed -i 's/name="Lead Vocals"/name="Audio 1"/g' "$SESSION_DIR/MyProject.ardour" 2>/dev/null || true
fi

# Launch Ardour with the existing session
launch_ardour_session "$SESSION_DIR/MyProject.ardour"

sleep 3

echo "=== Task setup complete ==="
echo "Agent should rename track 'Audio 1' to 'Lead Vocals'"
