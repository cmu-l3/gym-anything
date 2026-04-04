#!/bin/bash
echo "=== Setting up add_statute_reference task ==="
source /workspace/scripts/task_utils.sh

# Find Jurism database
JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    # Try to find it again or fail gracefully
    for db_candidate in /home/ga/Jurism/jurism.sqlite /home/ga/Jurism/zotero.sqlite; do
        if [ -f "$db_candidate" ]; then
            JURISM_DB="$db_candidate"
            break
        fi
    done
fi

if [ -z "$JURISM_DB" ]; then
    echo "FATAL: Jurism DB not found. Task cannot proceed."
    exit 1
fi

echo "Using database: $JURISM_DB"

# Stop Jurism to allow DB operations
echo "Stopping Jurism..."
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# 1. Clean up any existing items that might conflict (Civil Rights Act)
# We want to ensure the agent creates a NEW one.
python3 -c "
import sqlite3
import sys

db_path = '$JURISM_DB'
try:
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    
    # Find items with 'Civil Rights Act' in any field
    c.execute('''
        SELECT DISTINCT i.itemID 
        FROM items i
        JOIN itemData id ON i.itemID = id.itemID
        JOIN itemDataValues idv ON id.valueID = idv.valueID
        WHERE idv.value LIKE '%Civil Rights Act%'
        AND i.itemTypeID NOT IN (1, 3, 31)
    ''')
    items_to_delete = [row[0] for row in c.fetchall()]
    
    if items_to_delete:
        print(f'Cleaning up {len(items_to_delete)} existing items...')
        for item_id in items_to_delete:
            # Delete itemData
            c.execute('DELETE FROM itemData WHERE itemID = ?', (item_id,))
            # Delete creators
            c.execute('DELETE FROM itemCreators WHERE itemID = ?', (item_id,))
            # Delete collection links
            c.execute('DELETE FROM collectionItems WHERE itemID = ?', (item_id,))
            # Delete the item itself
            c.execute('DELETE FROM items WHERE itemID = ?', (item_id,))
        
        conn.commit()
    else:
        print('No conflicting items found.')
        
    conn.close()
except Exception as e:
    print(f'Error during cleanup: {e}')
"

# 2. Ensure library isn't totally empty (looks better if populated)
ITEM_COUNT=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1,3,31)" 2>/dev/null || echo "0")
if [ "$ITEM_COUNT" -lt 3 ]; then
    echo "Injecting background references..."
    python3 /workspace/utils/inject_references.py "$JURISM_DB" 2>/dev/null || true
fi

# 3. Record initial state
date +%s > /tmp/task_start_timestamp
INITIAL_COUNT=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1,3,31)" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_item_count
echo "Initial item count: $INITIAL_COUNT"

# 4. Relaunch Jurism
echo "Relaunching Jurism..."
setsid sudo -u ga bash -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus DISPLAY=:1 /opt/jurism/jurism --no-remote > /home/ga/jurism.log 2>&1 &'
sleep 5

# Wait for Jurism and dismiss dialogs
wait_and_dismiss_jurism_alerts 45

# Maximize
DISPLAY=:1 wmctrl -r "Jurism" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Jurism" 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="