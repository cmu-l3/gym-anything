#!/bin/bash
echo "=== Setting up add_dataset_reference task ==="
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Find Jurism database
JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    # Try to start Jurism once to initialize if missing (should be handled by env setup, but safety first)
    ensure_jurism_running
    JURISM_DB=$(get_jurism_db)
fi

echo "Using database: $JURISM_DB"

# Stop Jurism to allow DB access/cleanup
echo "Stopping Jurism for cleanup..."
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# Clean up any existing "Supreme Court Database" items to ensure clean state
if [ -f "$JURISM_DB" ]; then
    python3 -c "
import sqlite3
try:
    conn = sqlite3.connect('$JURISM_DB')
    c = conn.cursor()
    # Find items with title like 'The Supreme Court Database'
    c.execute('''
        SELECT items.itemID FROM items 
        JOIN itemData ON items.itemID = itemData.itemID 
        JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
        WHERE itemDataValues.value LIKE '%Supreme Court Database%'
    ''')
    ids = [row[0] for row in c.fetchall()]
    if ids:
        print(f'Removing {len(ids)} existing items...')
        for iid in ids:
            c.execute('DELETE FROM items WHERE itemID=?', (iid,))
            c.execute('DELETE FROM itemData WHERE itemID=?', (iid,))
            c.execute('DELETE FROM itemCreators WHERE itemID=?', (iid,))
            c.execute('DELETE FROM collectionItems WHERE itemID=?', (iid,))
        conn.commit()
    else:
        print('No existing items to remove.')
    conn.close()
except Exception as e:
    print(f'Error during cleanup: {e}')
" 2>&1
fi

# Ensure Jurism is running
echo "Starting Jurism..."
ensure_jurism_running

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="