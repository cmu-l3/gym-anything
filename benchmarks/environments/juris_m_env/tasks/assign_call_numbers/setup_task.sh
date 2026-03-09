#!/bin/bash
echo "=== Setting up assign_call_numbers task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Source utilities
source /workspace/scripts/task_utils.sh

# Ensure Jurism is running
ensure_jurism_running

# Get database path
DB_PATH=$(get_jurism_db)
if [ -z "$DB_PATH" ]; then
    echo "ERROR: Jurism database not found"
    exit 1
fi

echo "Database: $DB_PATH"

# Inject legal references if library is sparse (ensure our targets exist)
# We use the python script which checks and inserts if needed
load_legal_references_to_db

# Prepare the database state:
# 1. Ensure target items exist.
# 2. Clear any existing call numbers for them (to ensure agent actually does the work).
python3 -c "
import sqlite3
import sys

db_path = '$DB_PATH'
targets = ['Brown v. Board', 'Miranda v. Arizona', 'Marbury v. Madison']
field_call_number = 14
field_case_name = 58
field_title = 1

try:
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    print(f'Checking {len(targets)} target cases...')
    for target in targets:
        # Find item ID (check both caseName=58 and title=1 just in case)
        cursor.execute('''
            SELECT items.itemID FROM items 
            JOIN itemData ON items.itemID = itemData.itemID 
            JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
            WHERE fieldID IN (?, ?) AND value LIKE ? AND itemTypeID NOT IN (1,3,31)
            LIMIT 1
        ''', (field_case_name, field_title, f'%{target}%'))
        
        row = cursor.fetchone()
        if row:
            item_id = row[0]
            print(f'  Found {target} (ID: {item_id}). Clearing call number...')
            # Delete existing call number data for this item
            cursor.execute('DELETE FROM itemData WHERE itemID=? AND fieldID=?', (item_id, field_call_number))
        else:
            print(f'  WARNING: Could not find target case: {target}')
            
    conn.commit()
    conn.close()
    print('Database preparation complete.')
except Exception as e:
    print(f'Error preparing database: {e}')
    sys.exit(1)
"

# Restart Jurism to reflect database changes (cleared call numbers)
echo "Restarting Jurism to apply state changes..."
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# Relaunch
setsid sudo -u ga bash -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus DISPLAY=:1 /opt/jurism/jurism --no-remote > /home/ga/jurism_task.log 2>&1 &'
sleep 10

# Dismiss any alerts
wait_and_dismiss_jurism_alerts 45

# Maximize and focus
DISPLAY=:1 wmctrl -r "Jurism" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Jurism" 2>/dev/null || true
sleep 1

# Scroll to top of list to ensure items might be visible (Home key)
DISPLAY=:1 xdotool key Home 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="