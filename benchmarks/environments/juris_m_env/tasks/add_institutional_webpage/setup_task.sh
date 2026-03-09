#!/bin/bash
echo "=== Setting up add_institutional_webpage task ==="
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

# Stop Jurism to allow DB access
echo "Stopping Jurism for DB operations..."
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# Remove any pre-existing items with the target title to ensure clean state
python3 -c "
import sqlite3
conn = sqlite3.connect('$JURISM_DB')
c = conn.cursor()
# Find itemIDs with title '2023 Merger Guidelines' (fieldID=1 is title)
c.execute('''
    SELECT DISTINCT items.itemID FROM items
    JOIN itemData ON items.itemID = itemData.itemID
    JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID
    WHERE fieldID=1 AND value LIKE '%2023 Merger Guidelines%'
''')
ids_to_delete = [row[0] for row in c.fetchall()]

if ids_to_delete:
    print(f'Cleaning up {len(ids_to_delete)} existing items...')
    for iid in ids_to_delete:
        c.execute('DELETE FROM itemData WHERE itemID=?', (iid,))
        c.execute('DELETE FROM itemCreators WHERE itemID=?', (iid,))
        c.execute('DELETE FROM collectionItems WHERE itemID=?', (iid,))
        c.execute('DELETE FROM items WHERE itemID=?', (iid,))
    conn.commit()
else:
    print('No clean up needed.')

conn.close()
" 2>&1 || echo "Warning: DB cleanup script failed"

# Remove journal file if exists
rm -f "${JURISM_DB}-journal" 2>/dev/null || true

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

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

# Take screenshot to verify start state
DISPLAY=:1 scrot /tmp/task_start.png 2>/dev/null || true

echo "=== Task setup complete ==="