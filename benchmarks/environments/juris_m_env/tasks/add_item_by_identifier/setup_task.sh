#!/bin/bash
echo "=== Setting up add_item_by_identifier task ==="
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Find Jurism database
JURISM_DB=""
for db_candidate in /home/ga/Jurism/jurism.sqlite /home/ga/Jurism/zotero.sqlite; do
    if [ -f "$db_candidate" ]; then
        JURISM_DB="$db_candidate"
        break
    fi
done

if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    exit 1
fi

echo "Using database: $JURISM_DB"

# Stop Jurism to allow DB access
echo "Stopping Jurism for DB operations..."
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# Cleanup: Remove any existing entries for "A Theory of Justice" to ensure a clean test
# This removes items where title contains "Theory of Justice" AND creator is "Rawls"
python3 -c "
import sqlite3
import sys

db_path = '$JURISM_DB'
try:
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    
    # Find items matching criteria
    c.execute('''
        SELECT DISTINCT i.itemID 
        FROM items i
        JOIN itemData id ON i.itemID = id.itemID
        JOIN itemDataValues idv ON id.valueID = idv.valueID
        JOIN itemCreators ic ON i.itemID = ic.itemID
        JOIN creators cr ON ic.creatorID = cr.creatorID
        WHERE i.itemTypeID != 14 
          AND id.fieldID = 1 
          AND idv.value LIKE '%Theory of Justice%'
          AND cr.lastName LIKE '%Rawls%'
    ''')
    
    items_to_delete = [row[0] for row in c.fetchall()]
    
    if items_to_delete:
        print(f'Removing {len(items_to_delete)} pre-existing matching items...')
        for iid in items_to_delete:
            c.execute('DELETE FROM itemData WHERE itemID=?', (iid,))
            c.execute('DELETE FROM itemCreators WHERE itemID=?', (iid,))
            c.execute('DELETE FROM collectionItems WHERE itemID=?', (iid,))
            c.execute('DELETE FROM itemNotes WHERE parentItemID=?', (iid,))
            c.execute('DELETE FROM itemTags WHERE itemID=?', (iid,))
            c.execute('DELETE FROM items WHERE itemID=?', (iid,))
        conn.commit()
    else:
        print('No pre-existing items found to remove.')
        
    conn.close()
except Exception as e:
    print(f'Error during cleanup: {e}')
"

# Remove verification file if it exists
rm -f /home/ga/Documents/identifier_import_result.txt

# Record initial item count
INITIAL_COUNT=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1,3,31)" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_item_count.txt
echo "Initial item count: $INITIAL_COUNT"

# Ensure library has *some* other items so it doesn't look empty (better realism)
if [ "$INITIAL_COUNT" -lt 5 ]; then
    echo "Injecting background references..."
    python3 /workspace/utils/inject_references.py "$JURISM_DB" 2>/dev/null || true
fi

# Relaunch Jurism
echo "Relaunching Jurism..."
setsid sudo -u ga bash -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus DISPLAY=:1 /opt/jurism/jurism --no-remote > /home/ga/jurism_restart.log 2>&1 &'
sleep 5

# Wait for Jurism to load and dismiss any in-app alert dialogs
wait_and_dismiss_jurism_alerts 45

# Maximize and focus Jurism window
DISPLAY=:1 wmctrl -r "Jurism" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Jurism" 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="