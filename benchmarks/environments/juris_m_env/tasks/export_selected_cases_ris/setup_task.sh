#!/bin/bash
set -e
echo "=== Setting up export_selected_cases_ris task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Clean up previous output
OUTPUT_FILE="/home/ga/Documents/landmark_cases.ris"
rm -f "$OUTPUT_FILE"
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Get database path
DB_PATH=$(get_jurism_db)
if [ -z "$DB_PATH" ]; then
    echo "ERROR: Cannot find Jurism database"
    exit 1
fi

echo "Using database: $DB_PATH"

# Stop Jurism to modify DB
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# Inject legal references (ensures the 3 required cases are present)
# We use the inject_references.py script which is available in utils
if [ -f "/workspace/utils/inject_references.py" ]; then
    echo "Injecting legal references..."
    # We run it even if items exist to ensure our specific targets are there
    python3 /workspace/utils/inject_references.py "$DB_PATH" 2>/dev/null || echo "Injection script returned status $?"
else
    echo "WARNING: Injection script not found at /workspace/utils/inject_references.py"
fi

# Relaunch Jurism to pick up new items
echo "Relaunching Jurism..."
setsid sudo -u ga bash -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus DISPLAY=:1 /opt/jurism/jurism --no-remote > /home/ga/jurism_task.log 2>&1 &'
sleep 8

# Dismiss any alerts (jurisdiction config, etc.)
wait_and_dismiss_jurism_alerts 60

# Maximize and focus Jurism window
DISPLAY=:1 wmctrl -r "Jurism" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Jurism" 2>/dev/null || true
sleep 2

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="