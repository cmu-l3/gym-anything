#!/bin/bash
set -e
echo "=== Setting up fix_allcaps_author_names task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Get database path
DB_PATH=$(get_jurism_db)
if [ -z "$DB_PATH" ]; then
    echo "ERROR: Cannot find Jurism database"
    exit 1
fi

echo "Using database: $DB_PATH"

# Kill Jurism before DB modifications to release lock
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# Create a python script to inject the bad data (ALL CAPS AUTHORS)
# We do this directly to ensure the data is "bad" in the specific way we want
cat > /tmp/inject_bad_data.py << 'EOF'
import sys
import sqlite3
import random
import string
from datetime import datetime

# Database path passed as argument
db_path = sys.argv[1]

BAD_REFERENCES = [
    {
        "type": "book",
        "title": "The Common Law",
        "authorFirst": "OLIVER WENDELL",
        "authorLast": "HOLMES",
        "date": "1881",
        "publisher": "Little, Brown",
        "place": "Boston"
    },
    {
        "type": "book",
        "title": "Leviathan",
        "authorFirst": "THOMAS",
        "authorLast": "HOBBES",
        "date": "1651",
        "publisher": "Andrew Crooke",
        "place": "London"
    },
    {
        "type": "book",
        "title": "The Spirit of Laws",
        "authorFirst": "CHARLES",
        "authorLast": "MONTESQUIEU",
        "date": "1748",
        "publisher": "Nourse",
        "place": "London"
    }
]

# Minimal field mapping for Jurism 6 schema
FIELD_IDS = {
    "title": 1,
    "date": 8,
    "publisher": 26,
    "place": 27
}
ITEM_TYPE_BOOK = 7
CREATOR_TYPE_AUTHOR = 1

def get_or_create_value(cursor, value):
    cursor.execute("SELECT valueID FROM itemDataValues WHERE value = ?", (value,))
    row = cursor.fetchone()
    if row:
        return row[0]
    cursor.execute("INSERT INTO itemDataValues (value) VALUES (?)", (value,))
    return cursor.lastrowid

def get_or_create_creator(cursor, first, last):
    # Check if this specific ALL CAPS creator exists
    cursor.execute("SELECT creatorID FROM creators WHERE firstName = ? AND lastName = ?", (first, last))
    row = cursor.fetchone()
    if row:
        return row[0]
    # Insert with fieldMode=0 (Two-field mode)
    cursor.execute("INSERT INTO creators (firstName, lastName, fieldMode) VALUES (?, ?, 0)", (first, last))
    return cursor.lastrowid

try:
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    # First, clean up any existing copies of these books to avoid confusion
    for ref in BAD_REFERENCES:
        print(f"Cleaning up previous instances of {ref['title']}...")
        # Find items with this title
        cursor.execute("""
            SELECT items.itemID FROM items 
            JOIN itemData ON items.itemID = itemData.itemID 
            JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
            WHERE fieldID=1 AND value=?
        """, (ref['title'],))
        items_to_delete = [row[0] for row in cursor.fetchall()]
        
        for item_id in items_to_delete:
            cursor.execute("DELETE FROM itemData WHERE itemID=?", (item_id,))
            cursor.execute("DELETE FROM itemCreators WHERE itemID=?", (item_id,))
            cursor.execute("DELETE FROM items WHERE itemID=?", (item_id,))
    
    print("Injecting bad references...")
    now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    
    for ref in BAD_REFERENCES:
        # Create Item
        key = ''.join(random.choices(string.ascii_uppercase + string.digits, k=8))
        cursor.execute(
            "INSERT INTO items (itemTypeID, dateAdded, dateModified, clientDateModified, libraryID, key) VALUES (?, ?, ?, ?, ?, ?)",
            (ITEM_TYPE_BOOK, now_str, now_str, now_str, 1, key)
        )
        item_id = cursor.lastrowid
        
        # Add Fields
        for field, value in ref.items():
            if field in FIELD_IDS:
                val_id = get_or_create_value(cursor, value)
                cursor.execute(
                    "INSERT INTO itemData (itemID, fieldID, valueID) VALUES (?, ?, ?)",
                    (item_id, FIELD_IDS[field], val_id)
                )
        
        # Add ALL CAPS Creator
        creator_id = get_or_create_creator(cursor, ref['authorFirst'], ref['authorLast'])
        cursor.execute(
            "INSERT INTO itemCreators (itemID, creatorID, creatorTypeID, orderIndex) VALUES (?, ?, ?, 0)",
            (item_id, creator_id, CREATOR_TYPE_AUTHOR)
        )
        print(f"  Inserted '{ref['title']}' with author {ref['authorLast']}, {ref['authorFirst']}")

    conn.commit()
    conn.close()
    print("Injection successful.")
except Exception as e:
    print(f"Error during injection: {e}")
    sys.exit(1)
EOF

# Run the injection script
python3 /tmp/inject_bad_data.py "$DB_PATH"

# Relaunch Jurism
echo "Relaunching Jurism..."
setsid sudo -u ga bash -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus DISPLAY=:1 /opt/jurism/jurism --no-remote > /home/ga/jurism_task.log 2>&1 &'
sleep 5

# Handle alerts and startup
wait_and_dismiss_jurism_alerts 45

# Ensure maximized
DISPLAY=:1 wmctrl -r "Jurism" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Jurism" 2>/dev/null || true

# Verify bad items are present visually in logs (for debugging)
ITEM_CHECK=$(jurism_query "SELECT COUNT(*) FROM items JOIN itemData ON items.itemID=itemData.itemID JOIN itemDataValues ON itemData.valueID=itemDataValues.valueID WHERE value='HOLMES'")
echo "Setup Verification: Items with value 'HOLMES' found: $ITEM_CHECK"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="