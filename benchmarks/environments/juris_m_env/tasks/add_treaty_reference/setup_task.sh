#!/bin/bash
set -e
echo "=== Setting up add_treaty_reference task ==="
source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming verification
date +%s > /tmp/task_start_timestamp

# Find Jurism database
JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    exit 1
fi
echo "Using database: $JURISM_DB"

# Stop Jurism to allow DB access/cleanup
echo "Stopping Jurism..."
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# CLEAN STATE: Remove any existing items that might match the target
# This ensures the agent must actually create the item
echo "Cleaning up existing target items..."
python3 -c "
import sqlite3
import sys

try:
    conn = sqlite3.connect('$JURISM_DB')
    cursor = conn.cursor()
    
    # Find items with title containing 'Vienna Convention'
    cursor.execute('''
        SELECT i.itemID FROM items i
        JOIN itemData id ON i.itemID = id.itemID
        JOIN itemDataValues idv ON id.valueID = idv.valueID
        JOIN fields f ON id.fieldID = f.fieldID
        WHERE f.fieldName = 'title' AND idv.value LIKE '%Vienna Convention%'
    ''')
    
    items_to_delete = [row[0] for row in cursor.fetchall()]
    
    if items_to_delete:
        print(f'Deleting {len(items_to_delete)} existing items...')
        for item_id in items_to_delete:
            # Delete item data
            cursor.execute('DELETE FROM itemData WHERE itemID = ?', (item_id,))
            cursor.execute('DELETE FROM itemCreators WHERE itemID = ?', (item_id,))
            cursor.execute('DELETE FROM itemTags WHERE itemID = ?', (item_id,))
            cursor.execute('DELETE FROM collectionItems WHERE itemID = ?', (item_id,))
            cursor.execute('DELETE FROM itemNotes WHERE parentItemID = ?', (item_id,))
            cursor.execute('DELETE FROM items WHERE itemID = ?', (item_id,))
        
        conn.commit()
        print('Cleanup complete.')
    else:
        print('No pre-existing items found.')
        
    conn.close()
except Exception as e:
    print(f'Error during cleanup: {e}')
" 2>&1

# Remove any lingering lock files
rm -f "${JURISM_DB}-journal" 2>/dev/null || true

# Record initial item count
INITIAL_COUNT=$(get_item_count)
echo "$INITIAL_COUNT" > /tmp/initial_item_count
echo "Initial item count: $INITIAL_COUNT"

# Relaunch Jurism
echo "Relaunching Jurism..."
ensure_jurism_running

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="