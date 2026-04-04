#!/bin/bash
set -e
echo "=== Setting up customize_library_columns task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Reset UI state to defaults (Critical for this task)
# Find profile directory
PROFILE_DIR=""
for profile_base in /home/ga/.jurism/jurism /home/ga/.zotero/zotero; do
    found=$(find "$profile_base" -maxdepth 1 -type d -name "*.default" 2>/dev/null | head -1)
    if [ -n "$found" ]; then
        PROFILE_DIR="$found"
        break
    fi
done

if [ -n "$PROFILE_DIR" ]; then
    echo "Resetting view settings in $PROFILE_DIR"
    # Delete xulstore.json to force columns to default state (Title, Creator, Date only)
    # Jurism recreates this file on exit/start if missing
    rm -f "$PROFILE_DIR/xulstore.json"
    echo "xulstore.json removed"
else
    echo "WARNING: Profile directory not found, cannot reset columns"
fi

# 2. Inject some data so the list isn't empty (Visual context for the agent)
# Ensure Jurism is stopped first so we can touch the DB if needed
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 2

JURISM_DB=$(get_jurism_db)
if [ -n "$JURISM_DB" ]; then
    # Inject references
    echo "Injecting sample references..."
    python3 /workspace/utils/inject_references.py "$JURISM_DB" 2>/dev/null || true
fi

# 3. Start Jurism
echo "Starting Jurism..."
setsid sudo -u ga bash -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus DISPLAY=:1 /opt/jurism/jurism --no-remote > /home/ga/jurism_task.log 2>&1 &'

# Wait for window
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Jurism"; then
        echo "Jurism window detected"
        break
    fi
    sleep 1
done

# Dismiss any alerts (jurisdiction setup, etc)
wait_and_dismiss_jurism_alerts 45

# Maximize and focus
DISPLAY=:1 wmctrl -r "Jurism" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Jurism" 2>/dev/null || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="