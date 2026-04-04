#!/bin/bash
set -e
echo "=== Setting up add_thesis_reference task ==="
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Find Jurism database
JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    exit 1
fi
echo "Using database: $JURISM_DB"

# Stop Jurism to allow DB access (DB is locked while Jurism runs)
echo "Stopping Jurism for setup..."
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# CLEANUP: Remove any existing references to Claude Shannon or this thesis
# This ensures the agent must actually create it, not just find an old one.
python3 -c "
import sqlite3
try:
    conn = sqlite3.connect('$JURISM_DB')
    c = conn.cursor()
    
    # Find items matching the target title
    c.execute('''
        SELECT DISTINCT items.itemID FROM items 
        JOIN itemData ON items.itemID = itemData.itemID 
        JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
        WHERE LOWER(value) LIKE '%symbolic analysis%switching circuits%'
    ''')
    items_to_delete = [row[0] for row in c.fetchall()]
    
    # Find items with Shannon as author
    c.execute('''
        SELECT DISTINCT itemCreators.itemID FROM itemCreators
        JOIN creators ON itemCreators.creatorID = creators.creatorID
        WHERE LOWER(creators.lastName) = 'shannon' AND LOWER(creators.firstName) LIKE '%claude%'
    ''')
    items_to_delete.extend([row[0] for row in c.fetchall()])
    
    items_to_delete = list(set(items_to_delete))
    
    if items_to_delete:
        print(f'Cleaning up {len(items_to_delete)} pre-existing items...')
        for iid in items_to_delete:
            c.execute('DELETE FROM itemData WHERE itemID=?', (iid,))
            c.execute('DELETE FROM itemCreators WHERE itemID=?', (iid,))
            c.execute('DELETE FROM collectionItems WHERE itemID=?', (iid,))
            c.execute('DELETE FROM itemNotes WHERE parentItemID=?', (iid,))
            c.execute('DELETE FROM items WHERE itemID=?', (iid,))
        conn.commit()
    else:
        print('No pre-existing target items found.')
        
    conn.close()
except Exception as e:
    print(f'Database cleanup warning: {e}')
" 2>&1

# Ensure library has some other items (so it's not suspiciously empty)
ITEM_COUNT=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1,3,31)" 2>/dev/null || echo "0")
if [ "$ITEM_COUNT" -lt 5 ]; then
    echo "Library is sparse, injecting background legal references..."
    python3 /workspace/utils/inject_references.py "$JURISM_DB" 2>/dev/null && echo "References loaded"
fi

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
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="