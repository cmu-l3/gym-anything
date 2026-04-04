#!/bin/bash
set -e
echo "=== Setting up consolidate_case_notes task ==="

# Source shared utilities
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

# Stop Jurism to allow DB access
echo "Stopping Jurism..."
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# 1. Clean up any existing Gideon items or notes to ensure clean state
python3 -c "
import sqlite3
import sys

db_path = '$JURISM_DB'
conn = sqlite3.connect(db_path)
c = conn.cursor()

# Find existing Gideon items
c.execute(\"SELECT items.itemID FROM items JOIN itemData ON items.itemID=itemData.itemID JOIN itemDataValues ON itemData.valueID=itemDataValues.valueID WHERE fieldID=58 AND value LIKE '%Gideon v. Wainwright%'\")
items = [r[0] for r in c.fetchall()]

for iid in items:
    # Delete children (notes)
    c.execute(\"DELETE FROM itemNotes WHERE itemID IN (SELECT itemID FROM items WHERE parentItemID=?)\", (iid,))
    c.execute(\"DELETE FROM itemData WHERE itemID IN (SELECT itemID FROM items WHERE parentItemID=?)\", (iid,))
    c.execute(\"DELETE FROM items WHERE parentItemID=?\", (iid,))
    
    # Delete the item itself
    c.execute(\"DELETE FROM itemData WHERE itemID=?\", (iid,))
    c.execute(\"DELETE FROM itemCreators WHERE itemID=?\", (iid,))
    c.execute(\"DELETE FROM collectionItems WHERE itemID=?\", (iid,))
    c.execute(\"DELETE FROM items WHERE itemID=?\", (iid,))

conn.commit()
print(f'Cleaned up {len(items)} existing Gideon items')
" 2>&1

# 2. Inject Gideon case and specific notes
# We use a python script to ensure proper linking of parent/child items
cat << 'EOF' > /tmp/inject_gideon_notes.py
import sqlite3
import sys
import random
import string
import time

db_path = sys.argv[1]
conn = sqlite3.connect(db_path)
c = conn.cursor()

def get_id():
    return ''.join(random.choices(string.ascii_uppercase + string.digits, k=8))

now = time.strftime('%Y-%m-%d %H:%M:%S')

# 1. Create Parent Item (Case)
key_parent = get_id()
c.execute("INSERT INTO items (itemTypeID, dateAdded, dateModified, clientDateModified, libraryID, key) VALUES (9, ?, ?, ?, 1, ?)", (now, now, now, key_parent))
parent_id = c.lastrowid

# Add Case Name "Gideon v. Wainwright" (fieldID 58)
c.execute("INSERT OR IGNORE INTO itemDataValues (value) VALUES ('Gideon v. Wainwright')")
c.execute("SELECT valueID FROM itemDataValues WHERE value = 'Gideon v. Wainwright'")
val_id = c.fetchone()[0]
c.execute("INSERT INTO itemData (itemID, fieldID, valueID) VALUES (?, 58, ?)", (parent_id, val_id))

# Add Date "1963" (fieldID 69 for case dateDecided or 8 for date)
c.execute("INSERT OR IGNORE INTO itemDataValues (value) VALUES ('1963')")
c.execute("SELECT valueID FROM itemDataValues WHERE value = '1963'")
val_id_date = c.fetchone()[0]
c.execute("INSERT INTO itemData (itemID, fieldID, valueID) VALUES (?, 69, ?)", (parent_id, val_id_date))

print(f"Created Parent Case: Gideon v. Wainwright (ID: {parent_id})")

# 2. Create Note 1 (Holding)
note_text_1 = "<strong>Holding:</strong> The Sixth Amendment right to counsel is a fundamental right applied to the states via the Fourteenth Amendment due process clause, and requires that indigent criminal defendants be provided counsel at trial."
key_note1 = get_id()

# Insert item type 1 (note)
c.execute("INSERT INTO items (itemTypeID, dateAdded, dateModified, clientDateModified, libraryID, key, parentItemID) VALUES (1, ?, ?, ?, 1, ?, ?)", (now, now, now, key_note1, parent_id))
note1_id = c.lastrowid

# Insert note content
c.execute("INSERT INTO itemNotes (itemID, note, title) VALUES (?, ?, ?)", (note1_id, f"<p>{note_text_1}</p>", ""))

# 3. Create Note 2 (Significance)
note_text_2 = "<strong>Significance:</strong> Overruled Betts v. Brady. This case incorporated the right to counsel to the states."
key_note2 = get_id()

c.execute("INSERT INTO items (itemTypeID, dateAdded, dateModified, clientDateModified, libraryID, key, parentItemID) VALUES (1, ?, ?, ?, 1, ?, ?)", (now, now, now, key_note2, parent_id))
note2_id = c.lastrowid

c.execute("INSERT INTO itemNotes (itemID, note, title) VALUES (?, ?, ?)", (note2_id, f"<p>{note_text_2}</p>", ""))

conn.commit()
print(f"Created 2 notes attached to parent {parent_id}")
EOF

python3 /tmp/inject_gideon_notes.py "$JURISM_DB"

# Relaunch Jurism
echo "Relaunching Jurism..."
setsid sudo -u ga bash -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus DISPLAY=:1 /opt/jurism/jurism --no-remote > /home/ga/jurism.log 2>&1 &'
sleep 5

# Wait for Jurism and handle alerts
wait_and_dismiss_jurism_alerts 60

# Maximize and Focus
DISPLAY=:1 wmctrl -r "Jurism" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Jurism" 2>/dev/null || true
sleep 1

# Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="