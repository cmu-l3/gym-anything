#!/bin/bash
set -e
echo "=== Setting up rename_tags task ==="

DB="/home/ga/Zotero/zotero.sqlite"

# 1. Stop Zotero
pkill -9 -f zotero 2>/dev/null || true
sleep 2

# 2. Seed library with papers
echo "Seeding library..."
# This script adds 18 papers (10 classic + 8 ML)
python3 /workspace/scripts/seed_library.py --mode all > /dev/null 2>&1

# 3. Apply initial "bad" tags via SQL
# We need to find itemIDs for papers and apply the old tags
echo "Applying initial tags..."

python3 << 'PYEOF'
import sqlite3
import random

db_path = "/home/ga/Zotero/zotero.sqlite"
conn = sqlite3.connect(db_path)
c = conn.cursor()

# Map tags to partial titles of papers that should have them
tag_map = {
    "ML": [
        "Attention Is All You Need", "BERT", "Language Models are Few-Shot", 
        "ImageNet", "Deep Residual", "Generative Adversarial", "Deep Learning"
    ],
    "NLP": [
        "Attention Is All You Need", "BERT", "Language Models are Few-Shot"
    ],
    "CV": [
        "ImageNet", "Deep Residual", "Generative Adversarial"
    ],
    "info theory": [
        "A Mathematical Theory of Communication", "The Mathematical Theory of Communication", "Minimum-Redundancy Codes"
    ],
    "comp sci": [
        "On Computable Numbers", "Connexion with Graphs", "Unsolvable Problem", "Recursive Functions"
    ]
}

# 1. Ensure tags exist in 'tags' table and get their IDs
tag_ids = {}
for tag_name in tag_map.keys():
    # Insert ignore to avoid duplicates if re-running
    c.execute("INSERT OR IGNORE INTO tags (name) VALUES (?)", (tag_name,))
    c.execute("SELECT tagID FROM tags WHERE name=?", (tag_name,))
    row = c.fetchone()
    if row:
        tag_ids[tag_name] = row[0]
    else:
        print(f"Error creating tag {tag_name}")

# 2. Apply tags to items
for tag_name, titles in tag_map.items():
    tag_id = tag_ids.get(tag_name)
    if not tag_id:
        continue
        
    for title_part in titles:
        # Find item ID
        query = f"SELECT i.itemID FROM items i JOIN itemData d ON i.itemID=d.itemID JOIN itemDataValues v ON d.valueID=v.valueID WHERE d.fieldID=1 AND v.value LIKE '%{title_part}%'"
        c.execute(query)
        items = c.fetchall()
        
        for item in items:
            item_id = item[0]
            # Link in itemTags (type 0 is standard tag)
            c.execute("INSERT OR IGNORE INTO itemTags (itemID, tagID, type) VALUES (?, ?, 0)", (item_id, tag_id))

conn.commit()
conn.close()
print("Tags applied successfully via Python/SQLite")
PYEOF

# 4. Record initial state for verification
INITIAL_ITEMTAGS=$(sqlite3 "$DB" "SELECT COUNT(*) FROM itemTags" 2>/dev/null || echo "0")
echo "$INITIAL_ITEMTAGS" > /tmp/initial_itemtags_count
date +%s > /tmp/task_start_time

# 5. Restart Zotero
echo "Starting Zotero..."
sudo -u ga bash -c 'DISPLAY=:1 /opt/zotero/zotero --no-remote > /home/ga/zotero.log 2>&1 &'

# Wait for Zotero window
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -q "Zotero"; then
        echo "Window found"
        break
    fi
    sleep 1
done

# Maximize and focus
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true
sleep 2

# Take setup screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="