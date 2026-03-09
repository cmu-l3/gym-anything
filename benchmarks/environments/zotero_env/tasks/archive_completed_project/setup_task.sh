#!/bin/bash
# Setup for archive_completed_project task
# Seeds library, creates a specific collection, and adds papers to it via SQLite

echo "=== Setting up archive_completed_project task ==="

DB="/home/ga/Zotero/zotero.sqlite"
DOCS_DIR="/home/ga/Documents"
mkdir -p "$DOCS_DIR"
chown ga:ga "$DOCS_DIR"

# ── 1. Stop Zotero (Critical for DB manipulation) ───────────────────────────
echo "Stopping Zotero..."
pkill -9 -f zotero 2>/dev/null || true
sleep 3

# ── 2. Seed Library ─────────────────────────────────────────────────────────
echo "Seeding library with ML papers..."
# This script populates items if empty
python3 /workspace/scripts/seed_library.py --mode ml > /dev/null 2>&1

# ── 3. Manipulate DB to create starting state ───────────────────────────────
# We need to create a collection "NeurIPS 2023 Draft" and add 3 specific papers to it

python3 << 'PYEOF'
import sqlite3
import random

DB_PATH = "/home/ga/Zotero/zotero.sqlite"
COLLECTION_NAME = "NeurIPS 2023 Draft"
TARGET_TITLES = [
    "Attention Is All You Need",
    "BERT: Pre-training of Deep Bidirectional Transformers for Language Understanding",
    "Language Models are Few-Shot Learners"
]

try:
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    
    # 1. Get Library ID
    cur.execute("SELECT libraryID FROM libraries WHERE type='user' LIMIT 1")
    res = cur.fetchone()
    library_id = res[0] if res else 1
    
    # 2. Check if collection already exists
    cur.execute("SELECT collectionID FROM collections WHERE collectionName=?", (COLLECTION_NAME,))
    res = cur.fetchone()
    
    if res:
        collection_id = res[0]
        print(f"Collection '{COLLECTION_NAME}' exists (ID: {collection_id})")
    else:
        # Create collection
        # Zotero 7 collections: collectionID, libraryID, key, parentCollectionID, collectionName, ...
        # We generate a random key (approximate Zotero behavior)
        key = ''.join(random.choices('ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789', k=8))
        cur.execute("""
            INSERT INTO collections (libraryID, key, collectionName)
            VALUES (?, ?, ?)
        """, (library_id, key, COLLECTION_NAME))
        collection_id = cur.lastrowid
        print(f"Created collection '{COLLECTION_NAME}' (ID: {collection_id})")

    # 3. Find target items
    target_ids = []
    for title in TARGET_TITLES:
        # Fuzzy match title in itemDataValues linked to fieldID 1 (title)
        cur.execute("""
            SELECT i.itemID FROM items i
            JOIN itemData d ON i.itemID = d.itemID
            JOIN itemDataValues v ON d.valueID = v.valueID
            WHERE d.fieldID = 1 AND v.value LIKE ?
        """, (f"%{title}%",))
        row = cur.fetchone()
        if row:
            target_ids.append(row[0])
            print(f"Found item '{title[:20]}...' -> ID {row[0]}")
        else:
            print(f"WARNING: Could not find item '{title}'")

    # 4. Add items to collection
    # collectionItems: collectionID, itemID, orderIndex (orderIndex is usually just int)
    for idx, item_id in enumerate(target_ids):
        # Check if already linked
        cur.execute("SELECT 1 FROM collectionItems WHERE collectionID=? AND itemID=?", (collection_id, item_id))
        if not cur.fetchone():
            cur.execute("INSERT INTO collectionItems (collectionID, itemID, orderIndex) VALUES (?, ?, ?)", 
                        (collection_id, item_id, idx))
            print(f"Linked item {item_id} to collection {collection_id}")

    # Save IDs to file for verification later
    with open("/tmp/target_item_ids.txt", "w") as f:
        f.write("\n".join(map(str, target_ids)))
        
    conn.commit()
    conn.close()
    
except Exception as e:
    print(f"Database setup failed: {e}")
    exit(1)
PYEOF

# Record task start time
date +%s > /tmp/task_start_time.txt

# ── 4. Restart Zotero ───────────────────────────────────────────────────────
echo "Restarting Zotero..."
sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid /opt/zotero/zotero --no-remote &"

# Wait for window
for i in $(seq 1 60); do
    if DISPLAY=:1 wmctrl -l | grep -qi "zotero"; then
        echo "Zotero window detected"
        break
    fi
    sleep 1
done

# Focus and Maximize
sleep 2
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
sleep 2
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="