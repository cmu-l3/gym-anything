#!/bin/bash
set -e
echo "=== Setting up edit_case_metadata task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Get the database path
DB_PATH=$(get_jurism_db)
if [ -z "$DB_PATH" ]; then
    echo "ERROR: Jurism database not found"
    # Try to find it manually as fallback
    DB_PATH=$(find /home/ga -name "jurism.sqlite" -o -name "zotero.sqlite" | head -n 1)
fi
echo "Database path: $DB_PATH"

# Kill Jurism to safely modify database
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# Inject legal references into the database (ensures Tinker case exists)
echo "Injecting references..."
python3 /workspace/utils/inject_references.py "$DB_PATH" 2>/dev/null
echo "References injected."

# Prepare the specific item state (Reset Tinker v. Des Moines)
# We need to ensure Date Decided is "1969" and Extra is empty.

python3 -c "
import sqlite3
import sys

db_path = '$DB_PATH'
try:
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    # 1. Find the Tinker item ID (fieldID 58 is caseName)
    cursor.execute('''
        SELECT i.itemID 
        FROM items i 
        JOIN itemData id ON i.itemID = id.itemID 
        JOIN itemDataValues idv ON id.valueID = idv.valueID 
        WHERE id.fieldID = 58 AND idv.value LIKE '%Tinker%'
        LIMIT 1
    ''')
    row = cursor.fetchone()
    
    if not row:
        print('Error: Tinker case not found after injection')
        sys.exit(1)
        
    item_id = row[0]
    print(f'Found Tinker itemID: {item_id}')
    
    # 2. Reset Date Decided (fieldID 69) to '1969'
    # Check if value '1969' exists in itemDataValues
    cursor.execute('SELECT valueID FROM itemDataValues WHERE value = ?', ('1969',))
    val_row = cursor.fetchone()
    if val_row:
        val_id = val_row[0]
    else:
        cursor.execute('INSERT INTO itemDataValues (value) VALUES (?)', ('1969',))
        val_id = cursor.lastrowid
        
    # Update or Insert the link in itemData
    cursor.execute('DELETE FROM itemData WHERE itemID = ? AND fieldID = 69', (item_id,))
    cursor.execute('INSERT INTO itemData (itemID, fieldID, valueID) VALUES (?, 69, ?)', (item_id, val_id))
    
    # 3. Clear Extra field (fieldID 18)
    cursor.execute('DELETE FROM itemData WHERE itemID = ? AND fieldID = 18', (item_id,))
    
    # 4. Touch dateModified to before task start
    cursor.execute(\"UPDATE items SET dateModified = datetime('now', '-1 day') WHERE itemID = ?\", (item_id,))
    
    conn.commit()
    conn.close()
    print('Tinker case metadata reset successfully')
except Exception as e:
    print(f'Database operation failed: {e}')
    sys.exit(1)
"

# Ensure proper ownership
chown ga:ga "$DB_PATH" 2>/dev/null || true

# Relaunch Jurism
echo "Starting Jurism..."
setsid sudo -u ga bash -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus DISPLAY=:1 /opt/jurism/jurism --no-remote > /home/ga/jurism_task.log 2>&1 &'
sleep 8

# Dismiss any startup alerts
wait_and_dismiss_jurism_alerts 45

# Maximize and focus Jurism
DISPLAY=:1 wmctrl -r "Jurism" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Jurism" 2>/dev/null || true
sleep 2

# Take initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="