#!/bin/bash
echo "=== Setting up add_map_reference task ==="
source /workspace/scripts/task_utils.sh

# Find Jurism database
JURISM_DB=$(get_jurism_db)

if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    # Try to initialize if missing (fallback logic similar to setup_jurism.sh)
    echo "Attempting to locate or initialize DB..."
    exit 1
fi

echo "Using database: $JURISM_DB"

# Stop Jurism to allow DB access
echo "Stopping Jurism for DB operations..."
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# Clean up any existing items that match the target to prevent false positives from previous runs
python3 -c "
import sqlite3
try:
    conn = sqlite3.connect('$JURISM_DB')
    c = conn.cursor()
    
    # Identify items with title 'Washington West, DC-MD-VA'
    c.execute('''
        SELECT itemData.itemID FROM itemData 
        JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
        JOIN fields ON itemData.fieldID = fields.fieldID
        WHERE fields.fieldName = 'title' AND itemDataValues.value LIKE '%Washington West%'
    ''')
    items_to_delete = [row[0] for row in c.fetchall()]
    
    if items_to_delete:
        print(f'Removing {len(items_to_delete)} pre-existing target items...')
        for iid in items_to_delete:
            # Delete associated data
            c.execute('DELETE FROM itemData WHERE itemID=?', (iid,))
            c.execute('DELETE FROM itemCreators WHERE itemID=?', (iid,))
            c.execute('DELETE FROM collectionItems WHERE itemID=?', (iid,))
            c.execute('DELETE FROM items WHERE itemID=?', (iid,))
            
    conn.commit()
    conn.close()
except Exception as e:
    print(f'Error cleaning DB: {e}')
" 2>&1

# Clean up journal file
rm -f "${JURISM_DB}-journal" 2>/dev/null || true

# Record start timestamp
date +%s > /tmp/task_start_timestamp

# Relaunch Jurism
echo "Relaunching Jurism..."
ensure_jurism_running

# Take screenshot to verify start state
take_screenshot /tmp/map_task_start.png

echo "=== Task setup complete ==="