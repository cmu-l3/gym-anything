#!/bin/bash
echo "=== Setting up add_letter_reference task ==="
source /workspace/scripts/task_utils.sh

# Find Jurism database
JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    exit 1
fi
echo "Using database: $JURISM_DB"

# Stop Jurism to allow DB access
echo "Stopping Jurism..."
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# 1. Clean up: Remove any existing "Letter from Birmingham Jail" to ensure fresh start
# We remove items where title matches
python3 -c "
import sqlite3
conn = sqlite3.connect('$JURISM_DB')
c = conn.cursor()
c.execute('''
    SELECT items.itemID FROM items
    JOIN itemData ON items.itemID = itemData.itemID
    JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID
    WHERE itemDataValues.value LIKE \"%Letter from Birmingham Jail%\"
''')
ids = [row[0] for row in c.fetchall()]
for iid in ids:
    c.execute('DELETE FROM itemData WHERE itemID=?', (iid,))
    c.execute('DELETE FROM itemCreators WHERE itemID=?', (iid,))
    c.execute('DELETE FROM collectionItems WHERE itemID=?', (iid,))
    c.execute('DELETE FROM itemNotes WHERE parentItemID=?', (iid,))
    c.execute('DELETE FROM items WHERE itemID=?', (iid,))
    print(f'Removed existing item {iid}')

# Also clear tags/collections to prevent clutter
c.execute('DELETE FROM itemTags')
c.execute('DELETE FROM tags')
c.execute('DELETE FROM collectionItems')
c.execute('DELETE FROM collections')
conn.commit()
conn.close()
" 2>&1 || echo "Cleanup warning"

# 2. Ensure library has some background items (inject if sparse)
ITEM_COUNT=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1,3,31)" 2>/dev/null || echo "0")
if [ "$ITEM_COUNT" -lt 5 ]; then
    echo "Injecting background legal references..."
    python3 /workspace/utils/inject_references.py "$JURISM_DB" 2>/dev/null
fi

# 3. Record start time and state
date +%s > /tmp/task_start_timestamp
INITIAL_COUNT=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1,3,31)" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_item_count

# 4. Relaunch Jurism
echo "Relaunching Jurism..."
setsid sudo -u ga bash -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus DISPLAY=:1 /opt/jurism/jurism --no-remote >> /home/ga/jurism.log 2>&1 &'
sleep 5

# Wait for load and dismiss alerts
wait_and_dismiss_jurism_alerts 45

# Maximize
DISPLAY=:1 wmctrl -r "Jurism" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Jurism" 2>/dev/null || true

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Library contains $INITIAL_COUNT items."