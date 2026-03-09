#!/bin/bash
echo "=== Setting up add_manual_case task ==="
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

# Ensure library has items (inject if needed)
ITEM_COUNT=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1,3,31)" 2>/dev/null || echo "0")
echo "Current item count: $ITEM_COUNT"

if [ "$ITEM_COUNT" -lt 5 ]; then
    echo "Library is sparse, loading legal references..."
    python3 /workspace/utils/inject_references.py "$JURISM_DB" 2>/dev/null && echo "References loaded" || echo "Warning: injection had issues"
    sleep 1
fi

# Remove pre-existing "Roe v. Wade" items to ensure a clean start state.
# Also clear collections and notes that may be residual from other tasks.
python3 -c "
import sqlite3
conn = sqlite3.connect('$JURISM_DB')
c = conn.cursor()
# Find and remove any Roe v. Wade case items (fieldID=58 is caseName)
c.execute('''SELECT DISTINCT items.itemID FROM items
    JOIN itemData ON items.itemID=itemData.itemID
    JOIN itemDataValues ON itemData.valueID=itemDataValues.valueID
    WHERE fieldID=58 AND LOWER(value) LIKE \"%roe%wade%\"''')
roe_ids = [row[0] for row in c.fetchall()]
for iid in roe_ids:
    c.execute('DELETE FROM itemData WHERE itemID=?', (iid,))
    c.execute('DELETE FROM itemCreators WHERE itemID=?', (iid,))
    c.execute('DELETE FROM collectionItems WHERE itemID=?', (iid,))
    c.execute('DELETE FROM items WHERE itemID=?', (iid,))
print(f'Removed {len(roe_ids)} pre-existing Roe v. Wade item(s)')
# Clear collections (residual from create_law_collection task)
c.execute('DELETE FROM collectionItems')
c.execute('DELETE FROM collections')
# Clear notes (residual from add_note_to_case task)
c.execute('DELETE FROM itemNotes')
c.execute('DELETE FROM items WHERE itemTypeID=31')
# Clear tags and integrityCheck to prevent Jurism rendering errors
c.execute('DELETE FROM itemTags')
c.execute('DELETE FROM tags')
c.execute(\"DELETE FROM settings WHERE setting='db' AND key='integrityCheck'\")
conn.commit()
conn.close()
" 2>&1 || echo "Warning: cleanup had issues"
rm -f "${JURISM_DB}-journal" 2>/dev/null || true

# Record start timestamp and initial item count
date +%s > /tmp/task_start_timestamp
INITIAL_COUNT=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1,3,31)" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_item_count_manual
echo "Initial item count (after cleanup): $INITIAL_COUNT"

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
DISPLAY=:1 import -window root /tmp/manual_case_task_start.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/manual_case_task_start.png 2>/dev/null || true

echo "=== Task setup complete ==="
echo "Library has $INITIAL_COUNT items (Roe v. Wade removed, collections/notes cleared)"
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"
