#!/bin/bash
set -e
echo "=== Setting up batch_tag_collection_items task ==="

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

# Kill Jurism before DB modifications to release lock
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# 1. Inject base legal references
# This ensures Gideon, Miranda, Obergefell, etc. exist in the library
python3 /workspace/utils/inject_references.py "$DB_PATH"
echo "Injected legal references"

# 2. Setup Collection and specific starting state via Python
# We need to:
# - Create the collection
# - Add specific items to it
# - Ensure NO existing 'due-process' tags exist on these items
cat > /tmp/setup_collection_tags.py << 'EOF'
import sqlite3
import sys
import random
import string

db_path = sys.argv[1]
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

# 1. Clean up any existing 'due-process' tags to ensure clean state
cursor.execute("SELECT tagID FROM tags WHERE name = 'due-process'")
existing_tag = cursor.fetchone()
if existing_tag:
    tag_id = existing_tag[0]
    cursor.execute("DELETE FROM itemTags WHERE tagID = ?", (tag_id,))
    cursor.execute("DELETE FROM tags WHERE tagID = ?", (tag_id,))
    print(f"Removed pre-existing 'due-process' tag (ID: {tag_id})")

# 2. Create Collection "Liberty & Due Process" if not exists
collection_name = "Liberty & Due Process"
cursor.execute("SELECT collectionID FROM collections WHERE collectionName = ?", (collection_name,))
row = cursor.fetchone()

if row:
    collection_id = row[0]
    # Clear existing items from it to be safe
    cursor.execute("DELETE FROM collectionItems WHERE collectionID = ?", (collection_id,))
    print(f"Cleared existing collection '{collection_name}' (ID: {collection_id})")
else:
    key = ''.join(random.choices(string.ascii_uppercase + string.digits, k=8))
    cursor.execute(
        "INSERT INTO collections (collectionName, libraryID, key, dateAdded, dateModified) VALUES (?, 1, ?, datetime('now'), datetime('now'))",
        (collection_name, key)
    )
    collection_id = cursor.lastrowid
    print(f"Created collection '{collection_name}' (ID: {collection_id})")

# 3. Find Target Items
target_cases = [
    "Gideon v. Wainwright",
    "Miranda v. Arizona",
    "Obergefell v. Hodges"
]

item_ids = []
for case in target_cases:
    # Find itemID by caseName (fieldID=58)
    cursor.execute("""
        SELECT itemID FROM itemData 
        JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
        WHERE fieldID=58 AND value LIKE ?
        LIMIT 1
    """, (f"%{case}%",))
    row = cursor.fetchone()
    if row:
        item_ids.append(row[0])
        print(f"Found item '{case}' (ID: {row[0]})")
    else:
        print(f"WARNING: Item '{case}' not found! Injection might have failed.")

# 4. Add Items to Collection
for index, item_id in enumerate(item_ids):
    cursor.execute(
        "INSERT OR IGNORE INTO collectionItems (collectionID, itemID, orderIndex) VALUES (?, ?, ?)",
        (collection_id, item_id, index)
    )

conn.commit()
conn.close()
EOF

python3 /tmp/setup_collection_tags.py "$DB_PATH"
echo "Collection setup complete"

# Record initial itemTag count for anti-gaming (should be 0 for this tag)
INITIAL_TAG_LINKS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM itemTags" 2>/dev/null || echo "0")
echo "$INITIAL_TAG_LINKS" > /tmp/initial_tag_link_count.txt

# Relaunch Jurism
echo "Relaunching Jurism..."
setsid sudo -u ga bash -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus DISPLAY=:1 /opt/jurism/jurism --no-remote > /home/ga/jurism.log 2>&1 &'
sleep 5

# Wait for Jurism to load and dismiss any in-app alert dialogs
wait_and_dismiss_jurism_alerts 45

# Maximize and Focus
DISPLAY=:1 wmctrl -r "Jurism" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Jurism" 2>/dev/null || true
sleep 1

# Reset selection (click somewhere neutral if possible, or just let it start)
# We won't force selection so the agent has to do it.

# Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true
echo "=== Task setup complete ==="