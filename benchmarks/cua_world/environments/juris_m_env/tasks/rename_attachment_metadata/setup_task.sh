#!/bin/bash
set -e
echo "=== Setting up rename_attachment_metadata task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Jurism is running
ensure_jurism_running

# Load legal references to ensure Marbury exists
load_legal_references_to_db

# Get DB path
DB_PATH=$(get_jurism_db)
if [ -z "$DB_PATH" ]; then
    echo "ERROR: Jurism database not found"
    exit 1
fi

echo "Using database: $DB_PATH"

# Stop Jurism for DB manipulation (safe injection)
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# Inject attachment using Python
python3 -c "
import sqlite3
import os
import sys
import shutil
import random
import string
import time

db_path = '$DB_PATH'
conn = sqlite3.connect(db_path)
c = conn.cursor()

# Find Marbury v. Madison
# Case Name field ID is 58 in Jurism/Zotero schema
query = \"\"\"
    SELECT i.itemID, i.key 
    FROM items i
    JOIN itemData id ON i.itemID = id.itemID
    JOIN itemDataValues idv ON id.valueID = idv.valueID
    WHERE (id.fieldID = 58 OR id.fieldID = 1) 
    AND idv.value LIKE '%Marbury%Madison%'
    LIMIT 1
\"\"\"
c.execute(query)
row = c.fetchone()

if not row:
    print('Error: Marbury v. Madison not found in DB')
    sys.exit(1)

parent_id, parent_key = row
print(f'Found Marbury: ID={parent_id}, Key={parent_key}')

# Remove any existing attachments for this item to ensure clean state
c.execute('SELECT itemID, key FROM items WHERE itemID IN (SELECT itemID FROM itemAttachments WHERE parentItemID=?)', (parent_id,))
existing_atts = c.fetchall()
for att_id, att_key in existing_atts:
    print(f'Removing existing attachment {att_key}')
    c.execute('DELETE FROM itemAttachments WHERE itemID=?', (att_id,))
    c.execute('DELETE FROM itemData WHERE itemID=?', (att_id,))
    c.execute('DELETE FROM items WHERE itemID=?', (att_id,))
    # Try to remove physical directory
    storage_path = f'/home/ga/Jurism/storage/{att_key}'
    if os.path.exists(storage_path):
        shutil.rmtree(storage_path)

# Generate new attachment key (8 chars)
att_key = ''.join(random.choices(string.ascii_uppercase + string.digits, k=8))
storage_dir = f'/home/ga/Jurism/storage/{att_key}'
os.makedirs(storage_dir, exist_ok=True)

# Create the PDF file
pdf_path = os.path.join(storage_dir, 'scan_generic.pdf')
with open(pdf_path, 'w') as f:
    f.write('%PDF-1.4\n%Dummy content for rename task\n')
print(f'Created file at {pdf_path}')

# Insert attachment item into DB
# itemTypeID 1 = attachment
now_str = time.strftime('%Y-%m-%d %H:%M:%S')
c.execute(
    'INSERT INTO items (itemTypeID, dateAdded, dateModified, libraryID, key) VALUES (1, ?, ?, 1, ?)',
    (now_str, now_str, att_key)
)
att_id = c.lastrowid

# Link attachment in itemAttachments
# linkMode 1 = imported file
c.execute(
    'INSERT INTO itemAttachments (itemID, parentItemID, linkMode, contentType, path) VALUES (?, ?, 1, \"application/pdf\", \"storage:scan_generic.pdf\")',
    (att_id, parent_id)
)

# Add title field (fieldID 1) for the attachment
c.execute('SELECT valueID FROM itemDataValues WHERE value = ?', ('scan_generic.pdf',))
val_row = c.fetchone()
if val_row:
    val_id = val_row[0]
else:
    c.execute('INSERT INTO itemDataValues (value) VALUES (?)', ('scan_generic.pdf',))
    val_id = c.lastrowid

c.execute('INSERT INTO itemData (itemID, fieldID, valueID) VALUES (?, 1, ?)', (att_id, val_id))

conn.commit()
conn.close()

# Save key for verification
with open('/tmp/task_att_key.txt', 'w') as f:
    f.write(att_key)
"

# Relaunch Jurism
echo "Relaunching Jurism..."
setsid sudo -u ga bash -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus DISPLAY=:1 /opt/jurism/jurism --no-remote >> /home/ga/jurism.log 2>&1 &'
sleep 5
wait_and_dismiss_jurism_alerts 45

# Maximize and focus
DISPLAY=:1 wmctrl -r "Jurism" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Jurism" 2>/dev/null || true

# Open the Marbury item in the UI if possible (by searching)
# Just focusing the app is usually enough, but we can type to search
DISPLAY=:1 xdotool key ctrl+f
sleep 0.5
DISPLAY=:1 xdotool type "Marbury"
sleep 1
DISPLAY=:1 xdotool key Return
sleep 0.5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="