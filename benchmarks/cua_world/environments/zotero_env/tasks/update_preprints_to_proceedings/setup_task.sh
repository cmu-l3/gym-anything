#!/bin/bash
echo "=== Setting up update_preprints_to_proceedings task ==="

DB="/home/ga/Zotero/zotero.sqlite"

# 1. Stop Zotero
echo "Stopping Zotero..."
pkill -9 -f zotero 2>/dev/null || true
sleep 3

# 2. Seed library with ML papers
echo "Seeding library..."
python3 /workspace/scripts/seed_library.py --mode ml > /dev/null

# 3. Modify database to downgrade specific papers to 'Report' and remove venue info
# We use python to robustly find IDs and execute SQL
python3 << 'PYEOF'
import sqlite3

db_path = "/home/ga/Zotero/zotero.sqlite"
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

target_papers = [
    "Attention Is All You Need",
    "Deep Residual Learning for Image Recognition",
    "Generative Adversarial Nets"
]

# Field IDs (Zotero Standard)
# 38: publicationTitle, 39: proceedingsTitle
venue_fields = [38, 39]
# Item Type IDs
# 27: Report
# 10: Conference Paper (Original likely)

print("Downgrading target papers to Report type and removing venue info...")

for title in target_papers:
    # Find item ID
    # fieldID 1 is title
    cursor.execute("""
        SELECT i.itemID 
        FROM items i 
        JOIN itemData d ON i.itemID = d.itemID 
        JOIN itemDataValues v ON d.valueID = v.valueID 
        WHERE d.fieldID=1 AND v.value=?
    """, (title,))
    row = cursor.fetchone()
    
    if row:
        item_id = row[0]
        print(f"Modifying '{title}' (ID: {item_id})")
        
        # 1. Change item type to Report (27)
        cursor.execute("UPDATE items SET itemTypeID=27 WHERE itemID=?", (item_id,))
        
        # 2. Remove venue fields (Publication/Proceedings Title)
        # We need to delete from itemData where fieldID is venue_field
        cursor.execute(f"DELETE FROM itemData WHERE itemID=? AND fieldID IN ({','.join(map(str, venue_fields))})", (item_id,))
        
    else:
        print(f"Warning: Paper '{title}' not found in DB")

conn.commit()
conn.close()
PYEOF

# Record timestamp
date +%s > /tmp/task_start_time.txt

# 4. Restart Zotero
echo "Restarting Zotero..."
sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid /opt/zotero/zotero --no-remote > /dev/null 2>&1 &"

# Wait for window
echo "Waiting for Zotero window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "zotero"; then
        echo "Window found."
        break
    fi
    sleep 1
done

# Maximize
sleep 5
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true

# Initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="