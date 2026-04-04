#!/bin/bash
echo "=== Setting up catalog_historical_manuscript task ==="
source /workspace/scripts/task_utils.sh

# Find Jurism database
JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    # Try to locate it again or fail gracefully
    JURISM_DB="/home/ga/Jurism/jurism.sqlite"
fi

echo "Using database: $JURISM_DB"

# Stop Jurism to allow DB access
echo "Stopping Jurism..."
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# Record task start time
date +%s > /tmp/task_start_timestamp

# Clean up any existing matching items to ensure a fresh start
if [ -f "$JURISM_DB" ]; then
    echo "Cleaning up existing Madison manuscript entries..."
    sqlite3 "$JURISM_DB" <<EOF
DELETE FROM itemData WHERE itemID IN (
    SELECT itemID FROM items 
    JOIN itemData USING (itemID) 
    JOIN itemDataValues USING (valueID) 
    WHERE value LIKE '%Notes of Debates%' OR value LIKE '%James Madison%'
);
DELETE FROM itemCreators WHERE itemID IN (
    SELECT itemID FROM items 
    JOIN itemData USING (itemID) 
    JOIN itemDataValues USING (valueID) 
    WHERE value LIKE '%Notes of Debates%'
);
DELETE FROM items WHERE itemID IN (
    SELECT itemID FROM items 
    JOIN itemData USING (itemID) 
    JOIN itemDataValues USING (valueID) 
    WHERE value LIKE '%Notes of Debates%'
);
EOF
    echo "Cleanup complete."
fi

# Relaunch Jurism
echo "Relaunching Jurism..."
setsid sudo -u ga bash -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus DISPLAY=:1 /opt/jurism/jurism --no-remote >> /home/ga/jurism.log 2>&1 &'
sleep 5

# Wait for Jurism and dismiss alerts
wait_and_dismiss_jurism_alerts 45

# Maximize and focus
DISPLAY=:1 wmctrl -r "Jurism" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Jurism" 2>/dev/null || true

# Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="