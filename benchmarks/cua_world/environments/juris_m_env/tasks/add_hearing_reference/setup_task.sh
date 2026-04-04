#!/bin/bash
echo "=== Setting up add_hearing_reference task ==="
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

# Stop Jurism for DB operations
echo "Stopping Jurism..."
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# Clean up any previous "Watergate" items to ensure a fresh start
# We look for items with "Watergate" in the title (fieldID=1)
python3 -c "
import sqlite3
import sys

db_path = '$JURISM_DB'
try:
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    
    # Find itemIDs with 'Watergate' in title
    c.execute('''
        SELECT DISTINCT items.itemID 
        FROM items 
        JOIN itemData ON items.itemID = itemData.itemID 
        JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
        WHERE fieldID = 1 AND value LIKE '%Watergate%'
    ''')
    items_to_delete = [row[0] for row in c.fetchall()]
    
    if items_to_delete:
        print(f'Cleaning up {len(items_to_delete)} previous Watergate items...')
        for iid in items_to_delete:
            c.execute('DELETE FROM itemData WHERE itemID=?', (iid,))
            c.execute('DELETE FROM itemCreators WHERE itemID=?', (iid,))
            c.execute('DELETE FROM collectionItems WHERE itemID=?', (iid,))
            c.execute('DELETE FROM itemNotes WHERE parentItemID=?', (iid,))
            c.execute('DELETE FROM items WHERE itemID=?', (iid,))
        conn.commit()
    else:
        print('No previous items found to clean.')
        
    conn.close()
except Exception as e:
    print(f'Error during cleanup: {e}')
" 2>&1

# Remove any lingering journal file
rm -f "${JURISM_DB}-journal" 2>/dev/null || true

# Record initial count of Hearing items (Hearing is usually itemTypeID=30, but we'll query by name if possible or assume 30)
# We'll use a safer query that joins itemTypes
INITIAL_HEARING_COUNT=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM items JOIN itemTypes ON items.itemTypeID = itemTypes.itemTypeID WHERE typeName = 'hearing'" 2>/dev/null || echo "0")
echo "$INITIAL_HEARING_COUNT" > /tmp/initial_hearing_count.txt
echo "Initial Hearing count: $INITIAL_HEARING_COUNT"

# Ensure Jurism is running
ensure_jurism_running

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="