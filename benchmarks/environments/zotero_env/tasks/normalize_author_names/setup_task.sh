#!/bin/bash
echo "=== Setting up normalize_author_names task ==="

# 1. Kill Zotero to modify DB safely
pkill -9 -f zotero 2>/dev/null || true
sleep 2

# 2. Seed the library with standard data first
echo "Seeding library..."
# We use 'all' mode to get the base papers, then modify them to be inconsistent
python3 /workspace/scripts/seed_library.py --mode all > /dev/null 2>&1

# 3. Inject Inconsistencies via Python/SQLite
# We need to make specific authors inconsistent on specific papers.
# By default, seed_library reuses creatorIDs. We must create NEW creator entries
# and link them to specific items to simulate inconsistency.

echo "Injecting name inconsistencies..."
python3 << 'EOF'
import sqlite3
import shutil

DB_PATH = "/home/ga/Zotero/zotero.sqlite"

def get_item_id(cursor, title_substring):
    cursor.execute("""
        SELECT i.itemID FROM items i
        JOIN itemData d ON i.itemID = d.itemID
        JOIN itemDataValues v ON d.valueID = v.valueID
        WHERE d.fieldID = 1 AND v.value LIKE ?
    """, (f"%{title_substring}%",))
    res = cursor.fetchone()
    return res[0] if res else None

def create_and_link_creator(cursor, item_id, old_last_name, new_first, new_last):
    if not item_id:
        return
    
    # 1. Create new creator
    cursor.execute("INSERT INTO creators (firstName, lastName, fieldMode) VALUES (?, ?, 0)", 
                   (new_first, new_last))
    new_creator_id = cursor.lastrowid
    
    # 2. Find the current link for the author we want to replace
    # We look for the creator link on this item where the linked creator has the old last name
    cursor.execute("""
        SELECT ic.itemCreatorID 
        FROM itemCreators ic
        JOIN creators c ON ic.creatorID = c.creatorID
        WHERE ic.itemID = ? AND c.lastName = ?
    """, (item_id, old_last_name))
    link_res = cursor.fetchone()
    
    if link_res:
        item_creator_id = link_res[0]
        # 3. Update the link to point to the new inconsistent creator
        cursor.execute("UPDATE itemCreators SET creatorID = ? WHERE itemCreatorID = ?", 
                       (new_creator_id, item_creator_id))
        print(f"Updated item {item_id}: Replaced {old_last_name} with {new_first} {new_last}")

try:
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()

    # Case 1: Turing on "On Computable Numbers" -> "A. M."
    # (Leave "Computing Machinery" as standard "Alan")
    tid = get_item_id(c, "Computable Numbers")
    create_and_link_creator(c, tid, "Turing", "A. M.", "Turing")

    # Case 2: Shannon on "A Mathematical Theory..." -> "C."
    # (Leave "The Mathematical Theory..." as "Claude E." or "Claude")
    sid1 = get_item_id(c, "A Mathematical Theory of Communication")
    create_and_link_creator(c, sid1, "Shannon", "C.", "Shannon")

    # Case 3: Shannon on "The Mathematical Theory..." -> "Claude" (no middle initial)
    sid2 = get_item_id(c, "The Mathematical Theory of Communication")
    create_and_link_creator(c, sid2, "Shannon", "Claude", "Shannon")

    # Case 4: Hinton on "ImageNet" -> "G."
    hid = get_item_id(c, "ImageNet Classification")
    create_and_link_creator(c, hid, "Hinton", "G.", "Hinton")

    conn.commit()
    conn.close()
except Exception as e:
    print(f"Error injecting data: {e}")
    exit(1)
EOF

# 4. Record Initial State
DB="/home/ga/Zotero/zotero.sqlite"
INITIAL_CREATOR_COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM creators" 2>/dev/null || echo "0")
echo "$INITIAL_CREATOR_COUNT" > /tmp/initial_creator_count
date +%s > /tmp/task_start_time

# 5. Restart Zotero
echo "Restarting Zotero..."
sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid /opt/zotero/zotero --no-remote &"

# Wait for window
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -q "Zotero"; then
        echo "Zotero window detected"
        break
    fi
    sleep 1
done

# Maximize and focus
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true

# Initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="