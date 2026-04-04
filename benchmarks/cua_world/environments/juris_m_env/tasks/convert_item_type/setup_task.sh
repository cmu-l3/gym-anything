#!/bin/bash
echo "=== Setting up convert_item_type task ==="
source /workspace/scripts/task_utils.sh

# Record task start timestamp (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Find Jurism database
JURISM_DB=""
for db_candidate in /home/ga/Jurism/jurism.sqlite /home/ga/Jurism/zotero.sqlite; do
    if [ -f "$db_candidate" ]; then
        JURISM_DB="$db_candidate"
        break
    fi
done

if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    exit 1
fi

echo "Using database: $JURISM_DB"

# Stop Jurism to allow DB access
echo "Stopping Jurism for DB operations..."
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# 1. Clean up previous runs
# Remove any existing Roe v. Wade items to ensure we insert a fresh wrong one
python3 -c "
import sqlite3
import sys

db_path = '$JURISM_DB'
try:
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    
    # Find items with title/caseName like Roe v. Wade
    c.execute('''
        SELECT DISTINCT items.itemID FROM items 
        JOIN itemData ON items.itemID = itemData.itemID 
        JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
        WHERE LOWER(value) LIKE '%roe%wade%'
    ''')
    item_ids = [row[0] for row in c.fetchall()]
    
    if item_ids:
        print(f'Removing {len(item_ids)} existing Roe v. Wade items...')
        placeholders = ','.join('?' * len(item_ids))
        c.execute(f'DELETE FROM itemData WHERE itemID IN ({placeholders})', item_ids)
        c.execute(f'DELETE FROM itemCreators WHERE itemID IN ({placeholders})', item_ids)
        c.execute(f'DELETE FROM collectionItems WHERE itemID IN ({placeholders})', item_ids)
        c.execute(f'DELETE FROM items WHERE itemID IN ({placeholders})', item_ids)
        conn.commit()
    
    conn.close()
except Exception as e:
    print(f'Error cleaning DB: {e}')
"

# 2. Inject standard background data if library is empty
ITEM_COUNT=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1,3,31)" 2>/dev/null || echo "0")
if [ "$ITEM_COUNT" -lt 5 ]; then
    echo "Library sparse, injecting background references..."
    python3 /workspace/utils/inject_references.py "$JURISM_DB"
fi

# 3. Inject the MISCLASSIFIED item (Roe v. Wade as Journal Article)
# itemTypeID 24 = Journal Article
# fieldID 1 = Title
# fieldID 2 = Abstract
echo "Injecting misclassified item..."
python3 -c "
import sqlite3
import random
import string
import time
from datetime import datetime

db_path = '$JURISM_DB'
conn = sqlite3.connect(db_path)
c = conn.cursor()

def get_or_create_value(val):
    c.execute('SELECT valueID FROM itemDataValues WHERE value = ?', (val,))
    row = c.fetchone()
    if row: return row[0]
    c.execute('INSERT INTO itemDataValues (value) VALUES (?)', (val,))
    return c.lastrowid

# Create item (Journal Article = 24)
# We set dateAdded slightly in the past so we can distinguish it from user actions
now = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
key = ''.join(random.choices(string.ascii_uppercase + string.digits, k=8))

c.execute(
    'INSERT INTO items (itemTypeID, dateAdded, dateModified, clientDateModified, libraryID, key) VALUES (?, ?, ?, ?, ?, ?)',
    (24, now, now, now, 1, key)
)
item_id = c.lastrowid

# Add Fields
# Title (1) = Roe v. Wade
vid_title = get_or_create_value('Roe v. Wade')
c.execute('INSERT INTO itemData (itemID, fieldID, valueID) VALUES (?, ?, ?)', (item_id, 1, vid_title))

# Abstract (2) = Description
vid_abs = get_or_create_value('Landmark Supreme Court decision on reproductive rights (Misclassified as Article).')
c.execute('INSERT INTO itemData (itemID, fieldID, valueID) VALUES (?, ?, ?)', (item_id, 2, vid_abs))

# Date (8) = 1973
vid_date = get_or_create_value('1973')
c.execute('INSERT INTO itemData (itemID, fieldID, valueID) VALUES (?, ?, ?)', (item_id, 8, vid_date))

conn.commit()
conn.close()
print(f'Injected misclassified itemID: {item_id}')
"

# Remove journal files
rm -f "${JURISM_DB}-journal" 2>/dev/null || true

# Relaunch Jurism
echo "Relaunching Jurism..."
setsid sudo -u ga bash -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus DISPLAY=:1 /opt/jurism/jurism --no-remote >> /home/ga/jurism.log 2>&1 &'
sleep 5

# Wait for Jurism and dismiss alerts
wait_and_dismiss_jurism_alerts 45

# Maximize
DISPLAY=:1 wmctrl -r "Jurism" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Jurism" 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/convert_task_start.png

echo "=== Task setup complete ==="