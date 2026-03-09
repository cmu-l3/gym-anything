#!/bin/bash
set -e
echo "=== Setting up add_video_reference task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Jurism is running
ensure_jurism_running

# Get DB path
DB_PATH=$(get_jurism_db)
if [ -z "$DB_PATH" ]; then
    echo "ERROR: Jurism database not found"
    exit 1
fi

echo "Using database: $DB_PATH"

# Clean up any existing items with title "Hot Coffee" to ensure a fresh start
# We do this while Jurism is running (it might require a restart to see changes, but preventing duplicates is key)
# Safest is to close Jurism, modify DB, restart.
echo "Cleaning up previous attempts..."
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

sqlite3 "$DB_PATH" <<EOF
DELETE FROM itemData WHERE itemID IN (
    SELECT items.itemID FROM items 
    JOIN itemData ON items.itemID = itemData.itemID 
    JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
    WHERE items.itemTypeID NOT IN (1,3,31) 
    AND itemData.fieldID = 1 
    AND LOWER(itemDataValues.value) = 'hot coffee'
);
DELETE FROM itemCreators WHERE itemID IN (
    SELECT items.itemID FROM items 
    JOIN itemData ON items.itemID = itemData.itemID 
    JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
    WHERE items.itemTypeID NOT IN (1,3,31) 
    AND itemData.fieldID = 1 
    AND LOWER(itemDataValues.value) = 'hot coffee'
);
DELETE FROM items WHERE itemID IN (
    SELECT items.itemID FROM items 
    JOIN itemData ON items.itemID = itemData.itemID 
    JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
    WHERE items.itemTypeID NOT IN (1,3,31) 
    AND itemData.fieldID = 1 
    AND LOWER(itemDataValues.value) = 'hot coffee'
);
EOF

# Restart Jurism
echo "Relaunching Jurism..."
setsid sudo -u ga bash -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus DISPLAY=:1 /opt/jurism/jurism --no-remote > /home/ga/jurism_task.log 2>&1 &'
sleep 5
wait_and_dismiss_jurism_alerts 60

# Maximize and focus
DISPLAY=:1 wmctrl -r "Jurism" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Jurism" 2>/dev/null || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="