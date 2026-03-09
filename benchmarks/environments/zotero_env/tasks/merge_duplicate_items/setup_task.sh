#!/bin/bash
echo "=== Setting up merge_duplicate_items task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

DB_PATH="/home/ga/Zotero/zotero.sqlite"

# 1. Stop Zotero (to safely modify DB)
echo "Stopping Zotero..."
pkill -9 -f zotero 2>/dev/null || true
sleep 3

# 2. Seed library with standard papers
echo "Seeding library..."
python3 /workspace/scripts/seed_library.py --mode all > /dev/null 2>&1

# 3. Create duplicates via Python script to handle DB logic cleanly
echo "Creating duplicates with specific metadata errors..."
cat > /tmp/create_duplicates.py << 'PYEOF'
import sqlite3
import random
import string
import time

DB_PATH = "/home/ga/Zotero/zotero.sqlite"
LIBRARY_ID = 1

def generate_key():
    return ''.join(random.choices(string.ascii_uppercase + string.digits, k=8))

def duplicate_item(conn, title_fragment, exclude_field_id=None, override_field_id=None, override_value=None):
    cur = conn.cursor()
    
    # Find original item
    # Note: Using fieldID=1 (title)
    cur.execute("""
        SELECT i.itemID, i.itemTypeID 
        FROM items i
        JOIN itemData d ON i.itemID = d.itemID
        JOIN itemDataValues v ON d.valueID = v.valueID
        WHERE d.fieldID = 1 AND v.value LIKE ? AND i.libraryID = ?
        LIMIT 1
    """, (f"%{title_fragment}%", LIBRARY_ID))
    
    row = cur.fetchone()
    if not row:
        print(f"Skipping {title_fragment}: Not found")
        return
    
    orig_id, item_type_id = row
    new_key = generate_key()
    
    # Insert new item
    cur.execute("""
        INSERT INTO items (itemTypeID, dateAdded, dateModified, clientDateModified, libraryID, key)
        VALUES (?, datetime('now'), datetime('now'), datetime('now'), ?, ?)
    """, (item_type_id, LIBRARY_ID, new_key))
    new_id = cur.lastrowid
    
    # Copy itemData
    # We select fieldID and valueID from original
    cur.execute("SELECT fieldID, valueID FROM itemData WHERE itemID = ?", (orig_id,))
    fields = cur.fetchall()
    
    for field_id, value_id in fields:
        # Skip excluded field (e.g., Volume)
        if exclude_field_id and field_id == exclude_field_id:
            continue
            
        # Handle override (e.g., Date)
        final_value_id = value_id
        if override_field_id and field_id == override_field_id:
            # Create new value for override
            cur.execute("INSERT OR IGNORE INTO itemDataValues (value) VALUES (?)", (override_value,))
            # If inserted, get id, else get existing id
            cur.execute("SELECT valueID FROM itemDataValues WHERE value = ?", (override_value,))
            final_value_id = cur.fetchone()[0]
            
        cur.execute("INSERT INTO itemData (itemID, fieldID, valueID) VALUES (?, ?, ?)", 
                   (new_id, field_id, final_value_id))
                   
    # Copy creators
    cur.execute("SELECT creatorID, creatorTypeID, orderIndex FROM itemCreators WHERE itemID = ?", (orig_id,))
    creators = cur.fetchall()
    for creator_id, creator_type_id, order_index in creators:
        cur.execute("INSERT INTO itemCreators (itemID, creatorID, creatorTypeID, orderIndex) VALUES (?, ?, ?, ?)",
                   (new_id, creator_id, creator_type_id, order_index))
                   
    print(f"Duplicated {title_fragment} -> New ID {new_id}")

try:
    conn = sqlite3.connect(DB_PATH)
    
    # 1. Duplicate "Attention Is All You Need" (Missing Volume: fieldID 19)
    duplicate_item(conn, "Attention Is All You Need", exclude_field_id=19)
    
    # 2. Duplicate "Deep Learning" (Missing DOI: fieldID 59)
    duplicate_item(conn, "Deep Learning", exclude_field_id=59)
    
    # 3. Duplicate "Mathematical Theory of Communication" (Missing Pages: fieldID 32)
    duplicate_item(conn, "Mathematical Theory of Communication", exclude_field_id=32)
    
    # 4. Duplicate "Computing Machinery and Intelligence" (Wrong Year: fieldID 6 -> 1951)
    duplicate_item(conn, "Computing Machinery and Intelligence", override_field_id=6, override_value="1951")
    
    conn.commit()
    conn.close()
except Exception as e:
    print(f"Error creating duplicates: {e}")
    exit(1)
PYEOF

python3 /tmp/create_duplicates.py
rm /tmp/create_duplicates.py

# 4. Restart Zotero to detect duplicates
echo "Restarting Zotero..."
# Use setsid to detach from shell so it persists
sudo -u ga bash -c "DISPLAY=:1 setsid /opt/zotero/zotero --no-remote > /home/ga/zotero.log 2>&1 &"

# Wait for Zotero window
echo "Waiting for Zotero to launch..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -q "Zotero"; then
        echo "Zotero window detected"
        break
    fi
    sleep 1
done
sleep 5

# Maximize window
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true

# 5. Record Initial State
INITIAL_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1, 14, 28) AND itemID NOT IN (SELECT itemID FROM deletedItems)" 2>/dev/null)
echo "$INITIAL_COUNT" > /tmp/initial_count.txt
date +%s > /tmp/task_start_time.txt

echo "Initial item count: $INITIAL_COUNT (Should be 22)"
if [ "$INITIAL_COUNT" -ne "22" ]; then
    echo "WARNING: Expected 22 items, found $INITIAL_COUNT"
fi

# Take screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="