#!/bin/bash
echo "=== Setting up add_missing_coauthors task ==="

DB="/home/ga/Zotero/zotero.sqlite"

# 1. Kill Zotero to ensure DB access
pkill -9 -f zotero 2>/dev/null || true
sleep 2

# 2. Seed the library with full data first
echo "Seeding library..."
python3 /workspace/scripts/seed_library.py --mode all > /dev/null 2>&1

# 3. Surgically remove co-authors from target papers
# We use Python to handle the DB logic cleanly
python3 << 'PYEOF'
import sqlite3
import os

db_path = "/home/ga/Zotero/zotero.sqlite"
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

targets = [
    "Attention Is All You Need",
    "Deep Residual Learning for Image Recognition",
    "Molecular Structure of Nucleic Acids: A Structure for Deoxyribose Nucleic Acid",
    "Generative Adversarial Nets"
]

print("Stripping co-authors from target papers...")

for title in targets:
    # Find item ID
    # Note: Title matching usually uses LIKE for robustness
    cursor.execute("""
        SELECT i.itemID FROM items i
        JOIN itemData d ON i.itemID=d.itemID
        JOIN itemDataValues v ON d.valueID=v.valueID
        WHERE d.fieldID=1 AND v.value LIKE ?
    """, (f"%{title}%",))
    
    row = cursor.fetchone()
    if row:
        item_id = row[0]
        print(f"  Found '{title}' (ID: {item_id})")
        
        # Keep only the first author (orderIndex 0)
        # itemCreators table: itemID, creatorID, creatorTypeID, orderIndex
        cursor.execute("""
            DELETE FROM itemCreators 
            WHERE itemID=? AND orderIndex > 0
        """, (item_id,))
        print(f"    Removed co-authors for ID {item_id}")
    else:
        print(f"  WARNING: Could not find paper '{title}'")

conn.commit()
conn.close()
PYEOF

# Record setup timestamp
date +%s > /tmp/task_start_time.txt

# 4. Restart Zotero
echo "Restarting Zotero..."
sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid /opt/zotero/zotero --no-remote &"

# 5. Wait for window
echo "Waiting for Zotero window..."
for i in $(seq 1 45); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "zotero"; then
        echo "Window found."
        break
    fi
    sleep 1
done

# 6. Maximize and Focus
sleep 2
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true

# 7. Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="