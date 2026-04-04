#!/bin/bash
set -e
echo "=== Setting up add_encyclopedia_reference task ==="
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

# Clean up any existing items with the target title to ensure a clean start
echo "Cleaning up existing target items..."
python3 -c "
import sqlite3
import sys

db_path = '$JURISM_DB'
target_title = 'Adverse Possession'

try:
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    # Find items with the title 'Adverse Possession' (fieldID 1)
    cursor.execute('''
        SELECT items.itemID FROM items 
        JOIN itemData ON items.itemID = itemData.itemID 
        JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
        WHERE fieldID = 1 AND value = ?
    ''', (target_title,))
    
    items_to_delete = [row[0] for row in cursor.fetchall()]
    
    if items_to_delete:
        print(f'Deleting {len(items_to_delete)} pre-existing item(s)...')
        for item_id in items_to_delete:
            cursor.execute('DELETE FROM itemData WHERE itemID = ?', (item_id,))
            cursor.execute('DELETE FROM itemCreators WHERE itemID = ?', (item_id,))
            cursor.execute('DELETE FROM collectionItems WHERE itemID = ?', (item_id,))
            cursor.execute('DELETE FROM itemNotes WHERE parentItemID = ?', (item_id,))
            cursor.execute('DELETE FROM items WHERE itemID = ?', (item_id,))
        conn.commit()
    else:
        print('No pre-existing items found.')
        
    conn.close()
except Exception as e:
    print(f'Error cleaning DB: {e}')
    sys.exit(1)
"

# Clean up journal file if it exists
rm -f "${JURISM_DB}-journal" 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# Start Jurism
echo "Starting Jurism..."
ensure_jurism_running

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="