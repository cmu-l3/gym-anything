#!/bin/bash
echo "=== Setting up add_crs_report task ==="
source /workspace/scripts/task_utils.sh

# Find Jurism database
JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    exit 1
fi
echo "Using database: $JURISM_DB"

# Stop Jurism to allow DB operations
echo "Stopping Jurism..."
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# CLEANUP: Remove any existing items that match the target report to ensure clean state
# We look for items with Report Number "R44235" or the specific Title
python3 -c "
import sqlite3
import sys

db_path = '$JURISM_DB'
try:
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    
    # 1. Identify Target Items
    # We find items that match our target criteria (Title or Report Number)
    # Note: Field IDs vary, so we join with fields table or check known IDs if possible.
    # Safe approach: Find itemIDs that have matching values in itemDataValues linked to specific fields
    
    target_ids = set()
    
    # Check for Report Number 'R44235'
    c.execute('''
        SELECT items.itemID FROM items 
        JOIN itemData ON items.itemID = itemData.itemID
        JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID
        JOIN fields ON itemData.fieldID = fields.fieldID
        WHERE fields.fieldName = 'reportNumber' AND itemDataValues.value = 'R44235'
    ''')
    target_ids.update(row[0] for row in c.fetchall())
    
    # Check for Title (fuzzy match)
    c.execute('''
        SELECT items.itemID FROM items 
        JOIN itemData ON items.itemID = itemData.itemID
        JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID
        WHERE itemData.fieldID = 1 AND itemDataValues.value LIKE '%Supreme Court Appointment Process%'
    ''')
    target_ids.update(row[0] for row in c.fetchall())

    if target_ids:
        print(f'Found {len(target_ids)} existing items to remove.')
        for iid in target_ids:
            # Delete related data
            c.execute('DELETE FROM itemData WHERE itemID=?', (iid,))
            c.execute('DELETE FROM itemCreators WHERE itemID=?', (iid,))
            c.execute('DELETE FROM itemNotes WHERE parentItemID=?', (iid,))
            c.execute('DELETE FROM itemTags WHERE itemID=?', (iid,))
            c.execute('DELETE FROM collectionItems WHERE itemID=?', (iid,))
            c.execute('DELETE FROM items WHERE itemID=?', (iid,))
        conn.commit()
    else:
        print('No conflicting items found.')

    conn.close()
except Exception as e:
    print(f'Error during cleanup: {e}')
"

# Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# Initial item count
INITIAL_COUNT=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1,3,31)" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_count.txt

# Relaunch Jurism
echo "Relaunching Jurism..."
setsid sudo -u ga bash -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus DISPLAY=:1 /opt/jurism/jurism --no-remote >> /home/ga/jurism.log 2>&1 &'
sleep 5

# Wait for Jurism and handle alerts
wait_and_dismiss_jurism_alerts 45

# Maximize and focus
DISPLAY=:1 wmctrl -r "Jurism" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Jurism" 2>/dev/null || true
sleep 1

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="