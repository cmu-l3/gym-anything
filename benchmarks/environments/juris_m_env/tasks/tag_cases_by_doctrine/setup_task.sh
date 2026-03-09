#!/bin/bash
echo "=== Setting up tag_cases_by_doctrine task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Find Jurism database
JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    # Try default location if utility fails
    JURISM_DB="/home/ga/Jurism/jurism.sqlite"
fi
echo "Using database: $JURISM_DB"

# Kill Jurism to safely modify DB
echo "Stopping Jurism..."
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# Inject legal references (ensures target items exist)
echo "Injecting legal references..."
python3 /workspace/utils/inject_references.py "$JURISM_DB" 2>/dev/null

# Clear ALL existing tags to ensure a clean start state
# This prevents "already tagged" scenarios and ensures the agent does the work
echo "Clearing existing tags..."
sqlite3 "$JURISM_DB" <<EOF
DELETE FROM itemTags;
DELETE FROM tags;
VACUUM;
EOF

# Verify cleanup
TAG_COUNT=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM itemTags" 2>/dev/null || echo "0")
echo "Tags after cleanup: $TAG_COUNT"
echo "$TAG_COUNT" > /tmp/initial_tag_count.txt

# Relaunch Jurism
echo "Starting Jurism..."
setsid sudo -u ga bash -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus DISPLAY=:1 /opt/jurism/jurism --no-remote > /home/ga/jurism.log 2>&1 &'
sleep 8

# Dismiss startup alerts (jurisdiction config, etc.)
wait_and_dismiss_jurism_alerts 45

# Maximize and focus Jurism window
DISPLAY=:1 wmctrl -r "Jurism" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Jurism" 2>/dev/null || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="