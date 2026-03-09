#!/bin/bash
# Setup for remove_from_collection task
# Seeds library and creates a specific collection with 12 items

echo "=== Setting up remove_from_collection task ==="

DB="/home/ga/Zotero/zotero.sqlite"
COLLECTION_NAME="Thesis References"

# ── 1. Stop Zotero ───────────────────────────────────────────────────────────
echo "Stopping Zotero..."
pkill -9 -f zotero 2>/dev/null || true
sleep 3

# ── 2. Seed library with 18 papers ───────────────────────────────────────────
echo "Seeding library..."
python3 /workspace/scripts/seed_library.py --mode all > /tmp/seed_output.txt 2>/tmp/seed_stderr.txt
if [ $? -ne 0 ]; then
    echo "ERROR: Seeding failed"
    cat /tmp/seed_stderr.txt
    exit 1
fi

# ── 3. Create Collection and Populate ────────────────────────────────────────
echo "Creating '$COLLECTION_NAME' collection..."

# Create collection using Python for easier ID handling
python3 << PYEOF
import sqlite3
import random

db_path = "$DB"
coll_name = "$COLLECTION_NAME"

conn = sqlite3.connect(db_path)
cursor = conn.cursor()

# 1. Create Collection
# Generate a random key (approximate Zotero format)
key = ''.join(random.choices('0123456789ABCDEF', k=8))
cursor.execute("INSERT INTO collections (collectionName, libraryID, key) VALUES (?, 1, ?)", (coll_name, key))
coll_id = cursor.lastrowid
print(f"Created collection ID: {coll_id}")

# 2. Get Item IDs
# We need to add specific papers.
# Papers to INCLUDE in collection (12 total):
# REMOVE GROUP (4):
remove_titles = [
    "On the Electrodynamics of Moving Bodies",
    "Molecular Structure of Nucleic Acids: A Structure for Deoxyribose Nucleic Acid",
    "Generative Adversarial Nets",
    "Mastering the Game of Go with Deep Neural Networks and Tree Search"
]
# KEEP GROUP (8):
keep_titles = [
    "On Computable Numbers, with an Application to the Entscheidungsproblem",
    "A Mathematical Theory of Communication",
    "Computing Machinery and Intelligence",
    "Attention Is All You Need",
    "BERT: Pre-training of Deep Bidirectional Transformers for Language Understanding",
    "Language Models are Few-Shot Learners",
    "Deep Learning",
    "Deep Residual Learning for Image Recognition"
]

all_titles = remove_titles + keep_titles
ids_to_add = []

for title in all_titles:
    # Find item ID by title (using LIKE for partial matching if needed, but exact is better here)
    cursor.execute("""
        SELECT i.itemID FROM items i
        JOIN itemData d ON i.itemID = d.itemID
        JOIN itemDataValues v ON d.valueID = v.valueID
        WHERE d.fieldID = 1 AND v.value = ?
    """, (title,))
    row = cursor.fetchone()
    if row:
        ids_to_add.append(row[0])
    else:
        print(f"WARNING: Title not found: {title}")

# 3. Add items to collectionItems
for item_id in ids_to_add:
    try:
        cursor.execute("INSERT INTO collectionItems (collectionID, itemID) VALUES (?, ?)", (coll_id, item_id))
    except sqlite3.IntegrityError:
        pass # Already exists

conn.commit()
conn.close()

# Save collection ID for verification
with open("/tmp/original_collection_id.txt", "w") as f:
    f.write(str(coll_id))
PYEOF

# ── 4. Record Initial State ──────────────────────────────────────────────────
# Timestamp
date +%s > /tmp/task_start_time.txt

# Initial count in collection
INITIAL_COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM collectionItems WHERE collectionID=$(cat /tmp/original_collection_id.txt)" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_collection_item_count.txt
echo "Collection created with $INITIAL_COUNT items"

# ── 5. Restart Zotero ────────────────────────────────────────────────────────
echo "Restarting Zotero..."
sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid /opt/zotero/zotero --no-remote &"

echo "Waiting for Zotero window..."
for i in $(seq 1 45); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "zotero"; then
        echo "Window found after ${i}s"
        break
    fi
    sleep 1
done

sleep 3
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take setup screenshot
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="