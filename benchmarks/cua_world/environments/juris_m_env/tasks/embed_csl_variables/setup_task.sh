#!/bin/bash
echo "=== Setting up embed_csl_variables task ==="
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

# Check item count and inject references if library is sparse
ITEM_COUNT=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1,3,31)" 2>/dev/null || echo "0")
echo "Current item count: $ITEM_COUNT"

if [ "$ITEM_COUNT" -lt 5 ]; then
    echo "Library is sparse, loading legal references..."
    python3 /workspace/utils/inject_references.py "$JURISM_DB" 2>/dev/null && echo "References loaded" || echo "Warning: Reference injection had issues"
    sleep 1
fi

# CLEAN START STATE: Clear the "Extra" field (fieldID=18) for our specific target items
# This ensures the agent must actually perform the task, not just find pre-existing data.
# We also clear potentially conflicting settings.
python3 -c "
import sqlite3
try:
    conn = sqlite3.connect('$JURISM_DB')
    c = conn.cursor()
    
    # Target titles
    targets = ['Path of the Law', 'Constitutional Fact Review', 'Due Process Clause']
    
    # fieldID 1 = title, fieldID 18 = extra
    for target in targets:
        # Find itemID
        c.execute('''
            SELECT items.itemID FROM items 
            JOIN itemData ON items.itemID = itemData.itemID 
            JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
            WHERE fieldID=1 AND value LIKE ?
        ''', (f'%{target}%',))
        
        rows = c.fetchall()
        for row in rows:
            iid = row[0]
            # Delete existing Extra field entry for this item
            c.execute('DELETE FROM itemData WHERE itemID=? AND fieldID=18', (iid,))
            print(f'Cleared Extra field for itemID {iid} ({target})')

    # Cleanup interface settings to avoid rendering bugs
    c.execute(\"DELETE FROM settings WHERE setting='db' AND key='integrityCheck'\")
    
    conn.commit()
    conn.close()
except Exception as e:
    print(f'Error during setup SQL: {e}')
"

# Remove any lingering journal file
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
DISPLAY=:1 import -window root /tmp/csl_task_start.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/csl_task_start.png 2>/dev/null || true

echo "=== Task setup complete ==="