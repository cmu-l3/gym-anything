#!/bin/bash
set -e
echo "=== Setting up task: add_book_creators ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure Jurism is running
ensure_jurism_running

DB_PATH=$(get_jurism_db)
if [ -z "$DB_PATH" ]; then
    echo "ERROR: Cannot find Jurism database"
    exit 1
fi

echo "Using database: $DB_PATH"

# Stop Jurism to perform DB operations safely
echo "Stopping Jurism for database setup..."
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# Inject the specific book item without creators
# using python to handle UUIDs/keys correctly if needed, or raw sqlite
# fieldID 1 = title, 8 = date, 2 = abstract
# itemTypeID 7 = book (standard Zotero/Jurism)

python3 -c "
import sqlite3
import random
import string
import time
from datetime import datetime

db_path = '$DB_PATH'
target_title = 'Commentaries on the Laws of England'

conn = sqlite3.connect(db_path)
c = conn.cursor()

# 1. Check if item exists
c.execute('''
    SELECT i.itemID FROM items i
    JOIN itemData id ON i.itemID = id.itemID
    JOIN itemDataValues idv ON id.valueID = idv.valueID
    WHERE id.fieldID = 1 AND idv.value = ?
''', (target_title,))
row = c.fetchone()

item_id = None
now_str = datetime.now().strftime('%Y-%m-%d %H:%M:%S')

if row:
    item_id = row[0]
    print(f'Found existing itemID: {item_id}')
    # Clear existing creators for this item to ensure clean state
    c.execute('DELETE FROM itemCreators WHERE itemID = ?', (item_id,))
    print('Cleared creators from existing item.')
else:
    # Create new item
    key = ''.join(random.choices(string.ascii_uppercase + string.digits, k=8))
    # Insert into items (itemTypeID 6 or 7 is usually Book, let's assume 7 based on env docs, or check)
    # Checking schema: usually Book is 2 in Zotero 5, but Jurism might differ.
    # Let's use a safe query to find Book type ID if possible, or fallback to 2 (Zotero standard)
    c.execute(\"SELECT itemTypeID FROM itemTypes WHERE typeName = 'book'\")
    type_row = c.fetchone()
    book_type_id = type_row[0] if type_row else 2
    
    c.execute('''
        INSERT INTO items (itemTypeID, dateAdded, dateModified, clientDateModified, libraryID, key)
        VALUES (?, ?, ?, ?, 1, ?)
    ''', (book_type_id, now_str, now_str, now_str, key))
    item_id = c.lastrowid
    print(f'Created new book itemID: {item_id} (TypeID: {book_type_id})')

    # Add Title
    c.execute('SELECT valueID FROM itemDataValues WHERE value = ?', (target_title,))
    v_row = c.fetchone()
    if v_row:
        title_vid = v_row[0]
    else:
        c.execute('INSERT INTO itemDataValues (value) VALUES (?)', (target_title,))
        title_vid = c.lastrowid
    
    # fieldID 1 is Title
    c.execute('INSERT OR IGNORE INTO itemData (itemID, fieldID, valueID) VALUES (?, 1, ?)', (item_id, title_vid))

    # Add Date (1803)
    date_val = '1803'
    c.execute('SELECT valueID FROM itemDataValues WHERE value = ?', (date_val,))
    v_row = c.fetchone()
    if v_row:
        date_vid = v_row[0]
    else:
        c.execute('INSERT INTO itemDataValues (value) VALUES (?)', (date_val,))
        date_vid = c.lastrowid
    
    # fieldID 8 is Date
    c.execute('INSERT OR IGNORE INTO itemData (itemID, fieldID, valueID) VALUES (?, 8, ?)', (item_id, date_vid))

conn.commit()
conn.close()
"

# Relaunch Jurism
echo "Relaunching Jurism..."
setsid sudo -u ga bash -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus DISPLAY=:1 /opt/jurism/jurism --no-remote > /home/ga/jurism_task.log 2>&1 &'
sleep 5

# Handle alerts
wait_and_dismiss_jurism_alerts 60

# Maximize
DISPLAY=:1 wmctrl -r "Jurism" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Jurism" 2>/dev/null || true

# Initial screenshot
take_screenshot /tmp/task_initial.png
echo "Initial screenshot saved."

echo "=== Task setup complete ==="