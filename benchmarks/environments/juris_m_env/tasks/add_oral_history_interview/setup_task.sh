#!/bin/bash
set -e
echo "=== Setting up add_oral_history_interview task ==="
source /workspace/scripts/task_utils.sh

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

# Stop Jurism to allow DB access (DB is locked while Jurism runs)
echo "Stopping Jurism for DB operations..."
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# Ensure library has items (inject if needed) so it doesn't look empty
ITEM_COUNT=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1,3,31)" 2>/dev/null || echo "0")
if [ "$ITEM_COUNT" -lt 5 ]; then
    echo "Library is sparse, loading background references..."
    python3 /workspace/utils/inject_references.py "$JURISM_DB" 2>/dev/null || echo "Warning: injection had issues"
fi

# Remove any pre-existing items matching the target title to ensure a clean start
echo "Cleaning up any existing versions of the target item..."
python3 -c "
import sqlite3
import sys

db_path = '$JURISM_DB'
try:
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    
    # Find items with title like 'Oral history interview with John Lewis'
    # Field 1 is Title
    c.execute('''
        SELECT items.itemID FROM items 
        JOIN itemData ON items.itemID = itemData.itemID 
        JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
        WHERE fieldID = 1 AND value LIKE '%Oral history interview with John Lewis%'
    ''')
    
    items_to_delete = [row[0] for row in c.fetchall()]
    
    for item_id in items_to_delete:
        print(f'Deleting pre-existing item {item_id}')
        c.execute('DELETE FROM itemData WHERE itemID=?', (item_id,))
        c.execute('DELETE FROM itemCreators WHERE itemID=?', (item_id,))
        c.execute('DELETE FROM collectionItems WHERE itemID=?', (item_id,))
        c.execute('DELETE FROM items WHERE itemID=?', (item_id,))
        
    conn.commit()
    conn.close()
except Exception as e:
    print(f'Error during cleanup: {e}')
"

# Remove lingering journal files
rm -f "${JURISM_DB}-journal" 2>/dev/null || true

# Record start timestamp
date +%s > /tmp/task_start_timestamp
echo "Task start time recorded"

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

# Take screenshot of initial state
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="