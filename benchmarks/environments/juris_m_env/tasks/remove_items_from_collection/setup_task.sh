#!/bin/bash
echo "=== Setting up remove_items_from_collection task ==="
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Find Jurism database
JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    exit 1
fi
echo "Using database: $JURISM_DB"

# Stop Jurism to allow DB access
echo "Stopping Jurism for setup..."
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# 1. Clean Slate: Clear existing items/collections to ensure known state
python3 -c "
import sqlite3
conn = sqlite3.connect('$JURISM_DB')
c = conn.cursor()
# Clear items (except system types)
c.execute('DELETE FROM itemCreators WHERE itemID IN (SELECT itemID FROM items WHERE itemTypeID NOT IN (1,3,14,31))')
c.execute('DELETE FROM itemData WHERE itemID IN (SELECT itemID FROM items WHERE itemTypeID NOT IN (1,3,14,31))')
c.execute('DELETE FROM collectionItems')
c.execute('DELETE FROM collections')
c.execute('DELETE FROM items WHERE itemTypeID NOT IN (1,3,14,31)')
c.execute('DELETE FROM deletedItems')
# Clear tags/settings to prevent rendering bugs
c.execute('DELETE FROM itemTags')
c.execute('DELETE FROM tags')
c.execute(\"DELETE FROM settings WHERE setting='db' AND key='integrityCheck'\")
conn.commit()
conn.close()
" 2>&1 || echo "Warning: DB clear had issues"

# 2. Inject Reference Data (10 real items)
echo "Injecting reference data..."
python3 /workspace/utils/inject_references.py "$JURISM_DB"

# 3. Create 'Brief Research' Collection and add ALL items to it
echo "Creating collection and linking items..."
python3 -c "
import sqlite3
import random
import string

conn = sqlite3.connect('$JURISM_DB')
c = conn.cursor()

# Create collection
key = ''.join(random.choices(string.ascii_uppercase + string.digits, k=8))
c.execute(\"INSERT INTO collections (collectionName, libraryID, key, version, dateAdded, dateModified) VALUES ('Brief Research', 1, ?, 1, datetime('now'), datetime('now'))\", (key,))
collection_id = c.lastrowid

# Get all regular items
c.execute(\"SELECT itemID FROM items WHERE itemTypeID NOT IN (1,3,14,31)\")
items = [row[0] for row in c.fetchall()]

# Add items to collection
for i, item_id in enumerate(items):
    c.execute(\"INSERT INTO collectionItems (collectionID, itemID, orderIndex) VALUES (?, ?, ?)\", (collection_id, item_id, i))

print(f\"Created collection {collection_id} with {len(items)} items\")
conn.commit()
conn.close()
"

# Remove journaling files
rm -f "${JURISM_DB}-journal" "${JURISM_DB}-wal" 2>/dev/null || true

# Relaunch Jurism
echo "Relaunching Jurism..."
setsid sudo -u ga bash -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus DISPLAY=:1 /opt/jurism/jurism --no-remote >> /home/ga/jurism.log 2>&1 &'
sleep 5

# Wait for Jurism and dismiss alerts
wait_and_dismiss_jurism_alerts 45

# Maximize window
DISPLAY=:1 wmctrl -r "Jurism" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2
DISPLAY=:1 wmctrl -a "Jurism" 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="