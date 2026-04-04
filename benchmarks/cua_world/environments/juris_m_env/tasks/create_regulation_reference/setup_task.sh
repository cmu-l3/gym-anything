#!/bin/bash
set -e
echo "=== Setting up create_regulation_reference task ==="
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_timestamp

# Find Jurism database
JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    exit 1
fi
echo "Using database: $JURISM_DB"

# Stop Jurism to allow DB access
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# Clean up any existing regulations or items that might conflict
# We want to ensure the agent creates a NEW one
echo "Cleaning existing regulation items..."
python3 -c "
import sqlite3
import sys

db_path = '$JURISM_DB'
try:
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    
    # Get regulation type ID
    c.execute(\"SELECT itemTypeID FROM itemTypes WHERE typeName='regulation'\")
    res = c.fetchone()
    if res:
        reg_type_id = res[0]
        # Delete items of this type (user items only)
        c.execute('DELETE FROM itemData WHERE itemID IN (SELECT itemID FROM items WHERE itemTypeID=?)', (reg_type_id,))
        c.execute('DELETE FROM itemCreators WHERE itemID IN (SELECT itemID FROM items WHERE itemTypeID=?)', (reg_type_id,))
        c.execute('DELETE FROM collectionItems WHERE itemID IN (SELECT itemID FROM items WHERE itemTypeID=?)', (reg_type_id,))
        c.execute('DELETE FROM items WHERE itemTypeID=?', (reg_type_id,))
        print(f'Deleted existing regulation items (Type ID: {reg_type_id})')
    
    conn.commit()
    conn.close()
except Exception as e:
    print(f'Error cleaning DB: {e}')
"

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

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="