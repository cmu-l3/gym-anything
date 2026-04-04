#!/bin/bash
echo "=== Setting up add_book_reference task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Find Jurism database
JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    # Try to find it one more time or wait for first run
    sleep 5
    JURISM_DB=$(get_jurism_db)
fi

if [ -n "$JURISM_DB" ]; then
    echo "Using database: $JURISM_DB"
    
    # Clean up any existing "Legal Process" items to ensure clean state
    # This prevents false positives from previous runs
    echo "Cleaning up previous attempts..."
    
    # We need to stop Jurism to modify DB safely
    pkill -f /opt/jurism/jurism 2>/dev/null || true
    sleep 2
    
    python3 -c "
import sqlite3
import sys

try:
    conn = sqlite3.connect('$JURISM_DB')
    c = conn.cursor()
    
    # Find items with 'Legal Process' in title
    c.execute('''
        SELECT i.itemID FROM items i
        JOIN itemData id ON i.itemID = id.itemID
        JOIN itemDataValues idv ON id.valueID = idv.valueID
        JOIN fields f ON id.fieldID = f.fieldID
        WHERE f.fieldName = 'title' AND idv.value LIKE '%Legal Process%'
    ''')
    ids_to_remove = [row[0] for row in c.fetchall()]
    
    if ids_to_remove:
        print(f'Removing {len(ids_to_remove)} existing items...')
        for iid in ids_to_remove:
            # Delete associated data
            c.execute('DELETE FROM itemData WHERE itemID=?', (iid,))
            c.execute('DELETE FROM itemCreators WHERE itemID=?', (iid,))
            c.execute('DELETE FROM collectionItems WHERE itemID=?', (iid,))
            c.execute('DELETE FROM itemNotes WHERE parentItemID=?', (iid,))
            c.execute('DELETE FROM items WHERE itemID=?', (iid,))
        conn.commit()
    else:
        print('No existing items found to clean.')
        
    conn.close()
except Exception as e:
    print(f'Error during cleanup: {e}')
" 
    
    # Record initial book count
    BOOK_TYPE_ID=$(sqlite3 "$JURISM_DB" "SELECT itemTypeID FROM itemTypes WHERE typeName = 'book' LIMIT 1" 2>/dev/null || echo "7")
    INITIAL_BOOK_COUNT=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM items WHERE itemTypeID = ${BOOK_TYPE_ID}" 2>/dev/null || echo "0")
    echo "$INITIAL_BOOK_COUNT" > /tmp/initial_book_count.txt
    echo "Initial book count: $INITIAL_BOOK_COUNT"
else
    echo "0" > /tmp/initial_book_count.txt
    echo "WARNING: Jurism database not found during setup"
fi

# Ensure Jurism is running
ensure_jurism_running

# Take initial screenshot
echo "Capturing initial state..."
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="