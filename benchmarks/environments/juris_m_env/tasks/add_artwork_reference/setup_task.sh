#!/bin/bash
set -e
echo "=== Setting up add_artwork_reference task ==="
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Find Jurism database
JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Jurism database not found"
    exit 1
fi
echo "Using database: $JURISM_DB"

# Stop Jurism to perform cleanup
echo "Stopping Jurism for cleanup..."
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# Clean up any previous attempts (remove items with the target title)
echo "Removing any pre-existing task artifacts..."
python3 -c "
import sqlite3
import sys

db_path = '$JURISM_DB'
target_title = 'The Problem We All Live With'

try:
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    
    # Find itemIDs with the matching title
    c.execute('''
        SELECT items.itemID FROM items 
        JOIN itemData ON items.itemID = itemData.itemID 
        JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
        JOIN fields ON itemData.fieldID = fields.fieldID
        WHERE fields.fieldName = 'title' AND itemDataValues.value LIKE ?
    ''', (target_title,))
    
    item_ids = [row[0] for row in c.fetchall()]
    
    if item_ids:
        print(f'Removing {len(item_ids)} existing items matching title...')
        for iid in item_ids:
            # Delete associated data
            c.execute('DELETE FROM itemData WHERE itemID=?', (iid,))
            c.execute('DELETE FROM itemCreators WHERE itemID=?', (iid,))
            c.execute('DELETE FROM itemNotes WHERE parentItemID=?', (iid,))
            c.execute('DELETE FROM collectionItems WHERE itemID=?', (iid,))
            c.execute('DELETE FROM items WHERE itemID=?', (iid,))
        conn.commit()
    else:
        print('No pre-existing items found.')
        
    conn.close()
except Exception as e:
    print(f'Error during cleanup: {e}')
"

# Remove db lock/journal if they exist
rm -f "${JURISM_DB}-journal" "${JURISM_DB}-wal" 2>/dev/null || true

# Ensure Jurism is running
echo "Starting Jurism..."
ensure_jurism_running

# Take initial screenshot
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="