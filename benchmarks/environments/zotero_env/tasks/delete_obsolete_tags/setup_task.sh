#!/bin/bash
# Setup for delete_obsolete_tags task
# Seeds library with papers and injects a mix of junk and good tags

set -e
echo "=== Setting up delete_obsolete_tags task ==="

DB_PATH="/home/ga/Zotero/zotero.sqlite"

# 1. Stop Zotero to ensure DB is not locked
echo "Stopping Zotero..."
pkill -9 -f zotero 2>/dev/null || true
sleep 3

# 2. Seed base library (Classic + ML papers)
echo "Seeding library with papers..."
python3 /workspace/scripts/seed_library.py --mode all > /dev/null 2>&1

# 3. Inject tags using Python for robust SQLite handling
echo "Injecting tags..."
python3 << 'PYEOF'
import sqlite3
import random

db_path = "/home/ga/Zotero/zotero.sqlite"
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

# Get all valid item IDs (excluding notes/attachments)
cursor.execute("SELECT itemID, itemTypeID FROM items WHERE itemTypeID NOT IN (1, 14) AND itemID NOT IN (SELECT itemID FROM deletedItems)")
items = [row[0] for row in cursor.fetchall()]

if not items:
    print("Error: No items found in database!")
    exit(1)

# Define tags
junk_tags = ["imported", "to-read-maybe", "uncategorized", "DUPLICATE", "_temp", "needs-review"]
good_tags = ["deep-learning", "computer-science", "information-theory", "physics", "NLP"]

all_tags = junk_tags + good_tags

# Insert tags into 'tags' table and get their IDs
tag_ids = {}
for tag_name in all_tags:
    # Check if exists first (seed_library might have added some)
    cursor.execute("SELECT tagID FROM tags WHERE name=?", (tag_name,))
    row = cursor.fetchone()
    if row:
        tag_ids[tag_name] = row[0]
    else:
        cursor.execute("INSERT INTO tags (name) VALUES (?)", (tag_name,))
        tag_ids[tag_name] = cursor.lastrowid

# Assign tags to items
# We want to ensure every tag is used at least once so it appears in the selector

# Helper to assign tag to random items
def assign_tag(tag_name, count):
    tid = tag_ids[tag_name]
    # Pick 'count' random items
    target_items = random.sample(items, min(count, len(items)))
    for iid in target_items:
        # Check if link exists
        cursor.execute("SELECT * FROM itemTags WHERE itemID=? AND tagID=?", (iid, tid))
        if not cursor.fetchone():
            cursor.execute("INSERT INTO itemTags (itemID, tagID, type) VALUES (?, ?, 0)", (iid, tid))

# Assign Junk Tags
assign_tag("imported", 8)
assign_tag("to-read-maybe", 4)
assign_tag("uncategorized", 3)
assign_tag("DUPLICATE", 2)
assign_tag("_temp", 3)
assign_tag("needs-review", 5)

# Assign Good Tags (trying to be somewhat logical is nice, but random is robust enough for existence check)
assign_tag("deep-learning", 6)
assign_tag("computer-science", 4)
assign_tag("information-theory", 3)
assign_tag("physics", 3)
assign_tag("NLP", 3)

conn.commit()
conn.close()
print("Tags injected successfully.")
PYEOF

# 4. Record initial state
echo "Recording initial state..."
INITIAL_TAG_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM tags" 2>/dev/null || echo "0")
echo "$INITIAL_TAG_COUNT" > /tmp/initial_tag_count.txt

INITIAL_ITEM_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1, 14, 28)" 2>/dev/null || echo "0")
echo "$INITIAL_ITEM_COUNT" > /tmp/initial_item_count.txt

# Record timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 5. Restart Zotero
echo "Restarting Zotero..."
# Use sudo to run as user 'ga' and set display variables correctly
sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid /opt/zotero/zotero --no-remote &"

# Wait for Zotero window
echo "Waiting for Zotero window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "zotero"; then
        echo "Window found."
        break
    fi
    sleep 1
done

# Ensure window is maximized and focused
sleep 5
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true

# 6. Capture setup screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="