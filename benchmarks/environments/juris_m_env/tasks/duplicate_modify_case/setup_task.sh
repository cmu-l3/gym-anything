#!/bin/bash
echo "=== Setting up duplicate_modify_case task ==="
source /workspace/scripts/task_utils.sh

# Find Jurism database
JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    # Try to locate it manually if helper fails
    for db_candidate in /home/ga/Jurism/jurism.sqlite /home/ga/Jurism/zotero.sqlite; do
        if [ -f "$db_candidate" ]; then
            JURISM_DB="$db_candidate"
            break
        fi
    done
fi

if [ -z "$JURISM_DB" ]; then
    echo "CRITICAL: Jurism DB not found. Creating directory structure."
    mkdir -p /home/ga/Jurism
fi

# Stop Jurism to allow DB operations (prevent locking)
echo "Stopping Jurism..."
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# Inject references to ensure the source item exists
# We need at least the standard set which includes Brown v. Board (1954)
echo "Injecting legal references..."
python3 /workspace/utils/inject_references.py "$JURISM_DB" 2>/dev/null && echo "References loaded" || echo "Warning: injection script returned error"

# CLEANUP: Remove any existing "Brown v. Board II" or "1955" entries to ensure clean state
# We keep the 1954 one.
if [ -f "$JURISM_DB" ]; then
    python3 -c "
import sqlite3
db_path = '$JURISM_DB'
conn = sqlite3.connect(db_path)
c = conn.cursor()

# Find items with 'Brown v. Board' AND '1955' or 'II' and delete them
c.execute('''
    SELECT DISTINCT items.itemID FROM items
    JOIN itemData ON items.itemID = itemData.itemID
    JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID
    WHERE (fieldID = 58 AND value LIKE '%Brown v. Board%II%')
       OR (fieldID = 69 AND value LIKE '%1955%')
''')
ids_to_remove = [row[0] for row in c.fetchall()]

if ids_to_remove:
    print(f'Removing {len(ids_to_remove)} stale Brown II items...')
    for iid in ids_to_remove:
        c.execute('DELETE FROM itemData WHERE itemID=?', (iid,))
        c.execute('DELETE FROM itemCreators WHERE itemID=?', (iid,))
        c.execute('DELETE FROM collectionItems WHERE itemID=?', (iid,))
        c.execute('DELETE FROM items WHERE itemID=?', (iid,))
    conn.commit()
else:
    print('Clean state verified (no Brown II items found).')

# Verify Original Exists
c.execute('''
    SELECT COUNT(*) FROM items
    JOIN itemData ON items.itemID = itemData.itemID
    JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID
    WHERE fieldID = 58 AND value LIKE 'Brown v. Board of Education'
''')
count = c.fetchone()[0]
print(f'Found {count} original Brown v. Board items.')
conn.close()
"
fi

# Record start time for anti-gaming (new item must be created after this)
date +%s > /tmp/task_start_timestamp

# Relaunch Jurism
echo "Relaunching Jurism..."
setsid sudo -u ga bash -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus DISPLAY=:1 /opt/jurism/jurism --no-remote >> /home/ga/jurism.log 2>&1 &'
sleep 5

# Wait for Jurism and dismiss alerts
wait_and_dismiss_jurism_alerts 45

# Maximize
DISPLAY=:1 wmctrl -r "Jurism" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Jurism" 2>/dev/null || true
sleep 1

# Take setup screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="