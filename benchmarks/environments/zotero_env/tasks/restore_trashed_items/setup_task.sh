#!/bin/bash
# Setup for restore_trashed_items task
# 1. Seeds library
# 2. Creates 'Thesis References' collection with 3 items
# 3. Moves 5 items to Trash
# 4. Records IDs for verification

echo "=== Setting up restore_trashed_items task ==="

DB="/home/ga/Zotero/zotero.sqlite"

# ── 1. Stop Zotero ───────────────────────────────────────────────────────────
echo "Stopping Zotero..."
pkill -9 -f zotero 2>/dev/null || true
sleep 3

# ── 2. Seed Data ─────────────────────────────────────────────────────────────
echo "Seeding library..."
# This script populates items, itemData, etc.
python3 /workspace/scripts/seed_library.py --mode all > /dev/null 2>/tmp/seed_err.txt

# ── 3. Configure Database State ──────────────────────────────────────────────
# We use Python to interact with SQLite for complex ID lookups and insertions
python3 << 'PYEOF'
import sqlite3
import json
import time

db_path = "/home/ga/Zotero/zotero.sqlite"
conn = sqlite3.connect(db_path)
cur = conn.cursor()

# Helper to find item ID by title
def get_id(title):
    cur.execute("""
        SELECT i.itemID FROM items i
        JOIN itemData d ON i.itemID = d.itemID
        JOIN itemDataValues v ON d.valueID = v.valueID
        WHERE d.fieldID = 1 AND v.value LIKE ?
    """, (f"%{title}%",))
    res = cur.fetchone()
    return res[0] if res else None

# 1. Define Papers
trashed_titles = [
    "A Mathematical Theory of Communication",
    "Computing Machinery and Intelligence",
    "A Note on Two Problems in Connexion with Graphs",
    "Attention Is All You Need",
    "Generative Adversarial Nets"
]

keep_titles = [
    "BERT: Pre-training of Deep Bidirectional Transformers for Language Understanding",
    "Deep Residual Learning for Image Recognition",
    "ImageNet Classification with Deep Convolutional Neural Networks"
]

# 2. Get IDs
trashed_ids = {}
keep_ids = {}

for t in trashed_titles:
    id = get_id(t)
    if id: trashed_ids[t] = id

for t in keep_titles:
    id = get_id(t)
    if id: keep_ids[t] = id

# 3. Create Collection "Thesis References"
cur.execute("INSERT INTO collections (collectionName, libraryID, key, parentCollectionID) VALUES (?, 1, ?, NULL)", 
            ("Thesis References", "THESISREF"))
collection_id = cur.lastrowid

# 4. Add "Keep" papers to collection
for title, item_id in keep_ids.items():
    cur.execute("INSERT INTO collectionItems (collectionID, itemID) VALUES (?, ?)", (collection_id, item_id))

# 5. Move "Trash" papers to deletedItems
# Zotero 7 uses a deletedItems table. The presence of an itemID here means it's in the trash.
# We also need to ensure they are NOT in the collection yet.
timestamp = time.strftime('%Y-%m-%d %H:%M:%S')
for title, item_id in trashed_ids.items():
    cur.execute("INSERT OR IGNORE INTO deletedItems (itemID, dateDeleted) VALUES (?, ?)", (item_id, timestamp))

conn.commit()
conn.close()

# Save IDs for export script / verification
data = {
    "trashed_ids": trashed_ids,
    "keep_ids": keep_ids,
    "collection_id": collection_id
}
with open("/tmp/restore_task_data.json", "w") as f:
    json.dump(data, f)

print(f"Setup complete. Trashed {len(trashed_ids)} items. Added {len(keep_ids)} items to collection {collection_id}.")
PYEOF

# ── 4. Restart Zotero ────────────────────────────────────────────────────────
echo "Restarting Zotero..."
sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid /opt/zotero/zotero --no-remote &"

echo "Waiting for Zotero window..."
for i in $(seq 1 45); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "zotero"; then
        echo "Window found."
        break
    fi
    sleep 1
done

# Focus and maximize
sleep 3
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Record start time
date +%s > /tmp/task_start_time

# Take setup screenshot
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="