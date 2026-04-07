#!/bin/bash
echo "=== Setting up mastering_chain_setup task ==="

source /workspace/scripts/task_utils.sh

# Kill any existing Ardour instances
kill_ardour
sleep 2

SESSION_DIR="/home/ga/Audio/sessions/MyProject"
SESSION_FILE="$SESSION_DIR/MyProject.ardour"
BACKUP_FILE="$SESSION_DIR/MyProject.ardour.clean_backup"

# Create backup of clean session on first run
if [ ! -f "$BACKUP_FILE" ] && [ -f "$SESSION_FILE" ]; then
    cp "$SESSION_FILE" "$BACKUP_FILE"
    echo "Created clean session backup"
fi

# Restore clean session
if [ -f "$BACKUP_FILE" ]; then
    cp "$BACKUP_FILE" "$SESSION_FILE"
    echo "Restored clean session from backup"
fi

# Launch Ardour with the existing session
launch_ardour_session "$SESSION_FILE"

# Wait a few seconds for session to fully load and stabilize
sleep 5

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Record session file's initial modification time 
# (done AFTER Ardour is fully loaded, since opening a session might touch the file)
if [ -f "$SESSION_FILE" ]; then
    stat -c %Y "$SESSION_FILE" 2>/dev/null > /tmp/session_start_mtime.txt
else
    echo "0" > /tmp/session_start_mtime.txt
fi

# Focus and maximize main window
DISPLAY=:1 wmctrl -r "MyProject" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "MyProject" 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="