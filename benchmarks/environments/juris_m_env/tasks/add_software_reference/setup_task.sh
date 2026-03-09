#!/bin/bash
echo "=== Setting up add_software_reference task ==="
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

# Clean up any existing R references to ensure clean state
# Matches items with title starting with "R: A Language"
python3 -c "
import sqlite3
try:
    conn = sqlite3.connect('$JURISM_DB')
    c = conn.cursor()
    # Find items with the specific title
    c.execute('''
        SELECT DISTINCT items.itemID FROM items
        JOIN itemData ON items.itemID = itemData.itemID
        JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID
        WHERE itemData.fieldID = 1 AND itemDataValues.value LIKE 'R: A Language%'
    ''')
    item_ids = [row[0] for row in c.fetchall()]
    
    if item_ids:
        print(f'Removing {len(item_ids)} existing R references...')
        for iid in item_ids:
            c.execute('DELETE FROM itemData WHERE itemID=?', (iid,))
            c.execute('DELETE FROM itemCreators WHERE itemID=?', (iid,))
            c.execute('DELETE FROM collectionItems WHERE itemID=?', (iid,))
            c.execute('DELETE FROM itemNotes WHERE parentItemID=?', (iid,))
            c.execute('DELETE FROM itemTags WHERE itemID=?', (iid,))
            c.execute('DELETE FROM items WHERE itemID=?', (iid,))
        conn.commit()
    else:
        print('No existing R references found.')
    conn.close()
except Exception as e:
    print(f'Error during cleanup: {e}')
"

# Record start time
date +%s > /tmp/task_start_timestamp

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
take_screenshot /tmp/software_task_start.png

echo "=== Task setup complete ==="