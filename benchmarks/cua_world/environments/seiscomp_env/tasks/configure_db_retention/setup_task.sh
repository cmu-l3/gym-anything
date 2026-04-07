#!/bin/bash
echo "=== Setting up configure_db_retention task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure core SeisComP services are running so the agent can test the script
ensure_scmaster_running

# Clean up any pre-existing script or directory to ensure clean state
rm -rf /home/ga/scripts/cleanup_events.sh 2>/dev/null || true

# Start terminal for the user if not already running
if ! pgrep -f "gnome-terminal" > /dev/null; then
    echo "Starting GNOME terminal..."
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga &"
    sleep 3
fi

# Focus and maximize terminal window
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="