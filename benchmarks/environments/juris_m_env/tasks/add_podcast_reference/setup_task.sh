#!/bin/bash
echo "=== Setting up add_podcast_reference task ==="
source /workspace/scripts/task_utils.sh

# Find Jurism database
JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    exit 1
fi

echo "Using database: $JURISM_DB"

# Stop Jurism to allow DB access
echo "Stopping Jurism for DB operations..."
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# Remove any pre-existing "The Alibi" items to ensure a clean start
# We remove items matching the title to prevent confusion
python3 -c "
import sqlite3
import sys

db_path = '$JURISM_DB'
try:
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    
    # Find items with title 'The Alibi'
    # Field 1 is usually Title, but we check generic value match linked to items
    c.execute('''
        SELECT DISTINCT items.itemID 
        FROM items 
        JOIN itemData ON items.itemID = itemData.itemID 
        JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
        WHERE itemDataValues.value = 'The Alibi'
    ''')
    
    ids_to_remove = [row[0] for row in c.fetchall()]
    
    if ids_to_remove:
        print(f'Removing {len(ids_to_remove)} existing items with title \"The Alibi\"...')
        for iid in ids_to_remove:
            c.execute('DELETE FROM itemData WHERE itemID=?', (iid,))
            c.execute('DELETE FROM itemCreators WHERE itemID=?', (iid,))
            c.execute('DELETE FROM collectionItems WHERE itemID=?', (iid,))
            c.execute('DELETE FROM itemNotes WHERE parentItemID=?', (iid,))
            c.execute('DELETE FROM items WHERE itemID=?', (iid,))
        conn.commit()
    else:
        print('No existing items found to clean up.')
        
    # Also clean up integrityCheck setting to prevent rendering bugs
    c.execute(\"DELETE FROM settings WHERE setting='db' AND key='integrityCheck'\")
    conn.commit()
    conn.close()
except Exception as e:
    print(f'Error during DB cleanup: {e}')
"

# Inject some background legal references if library is too empty
# This ensures the 'New Item' menu isn't the only thing on screen
ITEM_COUNT=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1,3,31)" 2>/dev/null || echo "0")
if [ "$ITEM_COUNT" -lt 5 ]; then
    echo "Library is sparse, loading background references..."
    python3 /workspace/utils/inject_references.py "$JURISM_DB" 2>/dev/null || true
fi

# Remove journal files
rm -f "${JURISM_DB}-journal" 2>/dev/null || true

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Relaunch Jurism
echo "Relaunching Jurism..."
setsid sudo -u ga bash -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus DISPLAY=:1 /opt/jurism/jurism --no-remote >> /home/ga/jurism.log 2>&1 &'
sleep 5

# Wait for Jurism to load and dismiss alerts
wait_and_dismiss_jurism_alerts 45

# Maximize and focus
DISPLAY=:1 wmctrl -r "Jurism" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Jurism" 2>/dev/null || true
sleep 1

# Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="