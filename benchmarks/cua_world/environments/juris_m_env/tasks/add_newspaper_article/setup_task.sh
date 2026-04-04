#!/bin/bash
set -e
echo "=== Setting up add_newspaper_article task ==="
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure Jurism is running
ensure_jurism_running

# Get database path
JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Jurism database not found"
    exit 1
fi

echo "Using database: $JURISM_DB"

# Stop Jurism temporarily for DB cleanup
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# CLEANUP: Remove any existing items that match the target to ensure a clean start
# We look for items with the specific title to remove them
python3 -c "
import sqlite3
import sys

db_path = '$JURISM_DB'
target_title = 'Supreme Court Ruling Makes Same-Sex Marriage a Right Nationwide'

try:
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    # Find items with matching title (fieldID 1 is title)
    cursor.execute('''
        SELECT items.itemID FROM items 
        JOIN itemData ON items.itemID = itemData.itemID 
        JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
        WHERE fieldID = 1 AND value LIKE ?
    ''', ('%' + target_title + '%',))
    
    items_to_remove = [row[0] for row in cursor.fetchall()]
    
    if items_to_remove:
        print(f'Removing {len(items_to_remove)} pre-existing matching items...')
        for item_id in items_to_remove:
            cursor.execute('DELETE FROM itemData WHERE itemID = ?', (item_id,))
            cursor.execute('DELETE FROM itemCreators WHERE itemID = ?', (item_id,))
            cursor.execute('DELETE FROM items WHERE itemID = ?', (item_id,))
        conn.commit()
    else:
        print('No pre-existing items found.')
        
    conn.close()
except Exception as e:
    print(f'Error during cleanup: {e}')
"

# Inject some background legal data if library is empty (context)
load_legal_references_to_db

# Record initial item count
INITIAL_COUNT=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1,3,31)" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_item_count.txt

# Relaunch Jurism
echo "Relaunching Jurism..."
setsid sudo -u ga bash -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus DISPLAY=:1 /opt/jurism/jurism --no-remote > /home/ga/jurism.log 2>&1 &'
sleep 5

# Dismiss alerts
wait_and_dismiss_jurism_alerts 45

# Ensure window is maximized
DISPLAY=:1 wmctrl -r "Jurism" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Jurism" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="