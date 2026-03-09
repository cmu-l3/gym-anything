#!/bin/bash
set -e
echo "=== Setting up relate_cases task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Find Jurism database
JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    exit 1
fi
echo "Using database: $JURISM_DB"

# Stop Jurism to allow DB access
echo "Stopping Jurism for DB operations..."
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# Inject legal references (ensures cases exist)
echo "Injecting/Ensuring legal references..."
python3 /workspace/utils/inject_references.py "$JURISM_DB"

# Clear any existing relations to ensure clean start state
echo "Clearing existing item relations..."
sqlite3 "$JURISM_DB" "DELETE FROM itemRelations;" 2>/dev/null
# Clean up potential journal files
rm -f "${JURISM_DB}-journal" 2>/dev/null || true

# Record initial relation count (should be 0)
INITIAL_REL_COUNT=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM itemRelations" 2>/dev/null || echo "0")
echo "$INITIAL_REL_COUNT" > /tmp/initial_relation_count.txt
echo "Initial relation count: $INITIAL_REL_COUNT"

# Relaunch Jurism
echo "Relaunching Jurism..."
setsid sudo -u ga bash -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus DISPLAY=:1 /opt/jurism/jurism --no-remote >> /home/ga/jurism.log 2>&1 &'
sleep 5

# Wait for Jurism to load and dismiss any in-app alert dialogs
wait_and_dismiss_jurism_alerts 45

# Maximize and focus Jurism window
DISPLAY=:1 wmctrl -r "Jurism" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Jurism" 2>/dev/null || true
sleep 1

# Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="