#!/bin/bash
echo "=== Setting up add_conference_paper_reference task ==="
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
echo "Stopping Jurism for cleanup..."
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# Remove any pre-existing items with this title to ensure clean state
python3 -c "
import sqlite3
try:
    conn = sqlite3.connect('$JURISM_DB')
    c = conn.cursor()
    # Find items with title 'Explainable Legal Prediction' (fieldID=1)
    c.execute('''
        SELECT items.itemID FROM items
        JOIN itemData ON items.itemID=itemData.itemID
        JOIN itemDataValues ON itemData.valueID=itemDataValues.valueID
        WHERE fieldID=1 AND LOWER(value) LIKE \"%explainable%legal%prediction%\"
    ''')
    ids = [row[0] for row in c.fetchall()]
    for iid in ids:
        print(f'Removing pre-existing item {iid}')
        c.execute('DELETE FROM itemData WHERE itemID=?', (iid,))
        c.execute('DELETE FROM itemCreators WHERE itemID=?', (iid,))
        c.execute('DELETE FROM collectionItems WHERE itemID=?', (iid,))
        c.execute('DELETE FROM itemNotes WHERE parentItemID=?', (iid,))
        c.execute('DELETE FROM items WHERE itemID=?', (iid,))
    conn.commit()
    conn.close()
except Exception as e:
    print(f'Cleanup warning: {e}')
" 2>&1

# Record start timestamp
date +%s > /tmp/task_start_timestamp

# Ensure library has some other items so it's not empty (inject if needed)
ITEM_COUNT=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1,3,31)" 2>/dev/null || echo "0")
if [ "$ITEM_COUNT" -lt 5 ]; then
    echo "Library is sparse, loading filler references..."
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

# Take screenshot to verify start state
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="