#!/bin/bash
echo "=== Setting up add_note_to_case task ==="
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

# Ensure library has items (inject if needed)
ITEM_COUNT=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1,3,31)" 2>/dev/null || echo "0")
echo "Current item count: $ITEM_COUNT"

if [ "$ITEM_COUNT" -lt 5 ]; then
    echo "Loading legal references..."
    python3 /workspace/utils/inject_references.py "$JURISM_DB" 2>/dev/null && echo "References loaded" || echo "Warning: injection had issues"
    sleep 1
fi

# Clear notes and collections so task starts in isolated state
python3 -c "
import sqlite3
conn = sqlite3.connect('$JURISM_DB')
c = conn.cursor()
# Clear collections (prevent cross-task state leakage from create_law_collection task)
c.execute('DELETE FROM collectionItems')
c.execute('DELETE FROM collections')
# Remove note items and their itemNotes rows
c.execute('DELETE FROM itemNotes')
c.execute('DELETE FROM items WHERE itemTypeID=31')
# Also clear tags and integrityCheck flag to avoid rendering bugs
c.execute('DELETE FROM itemTags')
c.execute('DELETE FROM tags')
c.execute(\"DELETE FROM settings WHERE setting='db' AND key='integrityCheck'\")
conn.commit()
c.execute('SELECT COUNT(*) FROM itemNotes')
c2 = conn.cursor()
c2.execute('SELECT COUNT(*) FROM collections')
print(f'Notes after clear: {c.fetchone()[0]}, collections: {c2.fetchone()[0]}')
conn.close()
" 2>&1 || echo "Warning: note/collection clear had issues"
rm -f "${JURISM_DB}-journal" 2>/dev/null || true

# Record initial note count (should be 0) and task start timestamp
INITIAL_NOTES=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM itemNotes" 2>/dev/null || echo "0")
echo "$INITIAL_NOTES" > /tmp/initial_note_count
date +%s > /tmp/task_start_timestamp
echo "Initial note count: $INITIAL_NOTES"

# Verify Brown v. Board of Education is present (fieldID=58 is caseName in Jurism 6)
BROWN=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM items JOIN itemData ON items.itemID = itemData.itemID JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID WHERE fieldID=58 AND value LIKE '%Brown%Board%'" 2>/dev/null || echo "0")
echo "Found $BROWN item(s) matching 'Brown v. Board of Education'"

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

# Take screenshot to verify state
DISPLAY=:1 import -window root /tmp/note_task_start.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/note_task_start.png 2>/dev/null || true

echo "=== Task setup complete ==="
FINAL_COUNT=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1,3,31)" 2>/dev/null || echo "locked")
echo "Library has $FINAL_COUNT items"
