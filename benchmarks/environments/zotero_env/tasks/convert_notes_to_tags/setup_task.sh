#!/bin/bash
echo "=== Setting up convert_notes_to_tags task ==="

DB="/home/ga/Zotero/zotero.sqlite"

# 1. Stop Zotero to modify DB safely
pkill -9 -f zotero 2>/dev/null || true
sleep 2

# 2. Seed library with papers
echo "Seeding library..."
python3 /workspace/scripts/seed_library.py --mode all > /dev/null 2>&1

# 3. Inject Notes
# We need to find itemIDs for the specific papers and inject notes
echo "Injecting status notes..."

python3 << 'PYEOF'
import sqlite3
import datetime

db_path = "/home/ga/Zotero/zotero.sqlite"
conn = sqlite3.connect(db_path)
cur = conn.cursor()

def get_item_id(title):
    cur.execute("""
        SELECT i.itemID FROM items i
        JOIN itemData d ON i.itemID=d.itemID
        JOIN itemDataValues v ON d.valueID=v.valueID
        WHERE d.fieldID=1 AND v.value LIKE ?
    """, (f"%{title}%",))
    res = cur.fetchone()
    return res[0] if res else None

def create_note(parent_id, content):
    if not parent_id:
        return
    
    # 1. Create item in items table (type 1 = note)
    now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    cur.execute("INSERT INTO items (itemTypeID, dateAdded, dateModified) VALUES (1, ?, ?)", (now, now))
    note_id = cur.lastrowid
    
    # 2. Add to itemNotes
    # note content is usually HTML wrapped in div
    html_content = f'<div data-schema-version="8">{content}</div>'
    cur.execute("INSERT INTO itemNotes (itemID, parentItemID, note, title) VALUES (?, ?, ?, ?)", 
                (note_id, parent_id, html_content, ""))
    
    print(f"Added note '{content}' to item {parent_id} (new noteID {note_id})")

# Targets
p1 = get_item_id("Attention Is All You Need")
create_note(p1, "Status: Urgent - review for transformer architecture")

p2 = get_item_id("Deep Learning")
create_note(p2, "Status: Urgent check citations")

p3 = get_item_id("Computing Machinery and Intelligence")
create_note(p3, "Status: Later (historical context)")

# Control
p4 = get_item_id("On the Electrodynamics of Moving Bodies")
create_note(p4, "Key reference for physics module")

conn.commit()
conn.close()
PYEOF

# 4. Record start time
date +%s > /tmp/task_start_time.txt

# 5. Restart Zotero
echo "Restarting Zotero..."
sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid /opt/zotero/zotero --no-remote > /dev/null 2>&1 &"

# Wait for window
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -q "Zotero"; then
        echo "Zotero window detected"
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true

# Initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="