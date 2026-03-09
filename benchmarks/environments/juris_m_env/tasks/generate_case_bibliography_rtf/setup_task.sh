#!/bin/bash
set -e
echo "=== Setting up generate_case_bibliography_rtf task ==="

source /workspace/scripts/task_utils.sh

# 1. Clean up previous run artifacts
rm -f /home/ga/Documents/warren_bibliography.rtf
rm -f /tmp/task_result.json

# 2. Get DB Path
DB_PATH=$(get_jurism_db)
if [ -z "$DB_PATH" ]; then
    echo "ERROR: Jurism database not found"
    exit 1
fi
echo "Using database: $DB_PATH"

# 3. Stop Jurism to ensure safe DB modification
echo "Stopping Jurism..."
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# 4. Inject Reference Data (if not present)
echo "Ensuring legal references are loaded..."
python3 /workspace/utils/inject_references.py "$DB_PATH"

# 5. Create 'Warren Court' collection and populate it
# Using python for reliable SQLite handling
echo "Configuring 'Warren Court' collection..."
python3 -c "
import sqlite3
import random
import string
import sys

db_path = '$DB_PATH'
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

try:
    # Get Library ID (usually 1 for user library)
    cursor.execute('SELECT libraryID FROM libraries WHERE type=\"user\" LIMIT 1')
    res = cursor.fetchone()
    if not res:
        print('Error: User library not found')
        sys.exit(1)
    lib_id = res[0]

    # Check/Create Collection
    col_name = 'Warren Court'
    cursor.execute('SELECT collectionID FROM collections WHERE collectionName = ? AND libraryID = ?', (col_name, lib_id))
    row = cursor.fetchone()

    if row:
        col_id = row[0]
        # Clear existing items to ensure clean state
        cursor.execute('DELETE FROM collectionItems WHERE collectionID = ?', (col_id,))
        print(f'Collection {col_name} exists (ID: {col_id}), cleared items')
    else:
        # Generate random key for Zotero sync compatibility (8 chars)
        key = ''.join(random.choices(string.ascii_uppercase + string.digits, k=8))
        cursor.execute('INSERT INTO collections (collectionName, libraryID, key, dateAdded, dateModified) VALUES (?, ?, ?, datetime(\"now\"), datetime(\"now\"))', (col_name, lib_id, key))
        col_id = cursor.lastrowid
        print(f'Created collection {col_name} (ID: {col_id})')

    # Find specific cases by searching title/caseName
    # Field 58 is caseName, Field 1 is title (sometimes used as fallback)
    target_cases = [
        'Brown v. Board of Education',
        'Gideon v. Wainwright',
        'Miranda v. Arizona'
    ]
    
    found_count = 0
    for case in target_cases:
        # Find itemID
        # Join ensures we check values associated with fields
        query = '''
            SELECT items.itemID 
            FROM items 
            JOIN itemData ON items.itemID = itemData.itemID 
            JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
            WHERE itemData.fieldID IN (1, 58) 
            AND itemDataValues.value LIKE ? 
            AND items.libraryID = ?
            LIMIT 1
        '''
        cursor.execute(query, (f'%{case}%', lib_id))
        item_res = cursor.fetchone()
        
        if item_res:
            item_id = item_res[0]
            # Add to collection
            cursor.execute('INSERT OR IGNORE INTO collectionItems (collectionID, itemID, orderIndex) VALUES (?, ?, 0)', (col_id, item_id))
            print(f'Added {case} (ID: {item_id}) to collection')
            found_count += 1
        else:
            print(f'WARNING: Could not find case {case} in database')

    conn.commit()
    print(f'Setup complete. Added {found_count} items to collection.')

except Exception as e:
    print(f'Error setting up collection: {e}')
    sys.exit(1)
finally:
    conn.close()
"

# 6. Record task start time
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded"

# 7. Restart Jurism
echo "Relaunching Jurism..."
setsid sudo -u ga bash -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus DISPLAY=:1 /opt/jurism/jurism --no-remote > /home/ga/jurism.log 2>&1 &'
sleep 5

# 8. Wait for window and dismiss alerts
wait_and_dismiss_jurism_alerts 60

# 9. Maximize and focus
DISPLAY=:1 wmctrl -r "Jurism" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Jurism" 2>/dev/null || true
sleep 2

# 10. Initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Setup complete ==="