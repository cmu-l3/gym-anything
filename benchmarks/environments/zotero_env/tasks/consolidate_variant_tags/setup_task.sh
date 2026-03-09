#!/bin/bash
# Setup for consolidate_variant_tags
# Seeds library and injects messy tags for the agent to clean up

echo "=== Setting up consolidate_variant_tags task ==="

DB="/home/ga/Zotero/zotero.sqlite"

# ── 1. Stop Zotero ───────────────────────────────────────────────────────────
echo "Stopping Zotero..."
pkill -9 -f zotero 2>/dev/null || true
sleep 3

# ── 2. Seed Standard Library ─────────────────────────────────────────────────
echo "Seeding library..."
# Use seed_library.py to populate the base items (Classic + ML papers)
python3 /workspace/scripts/seed_library.py --mode all > /dev/null 2>/tmp/seed_err.txt
if [ $? -ne 0 ]; then
    echo "Seed failed:"
    cat /tmp/seed_err.txt
    exit 1
fi

# ── 3. Inject Messy Tags via SQLite ──────────────────────────────────────────
# We need to manually insert tags and assign them to items to create the mess.
# Zotero 7 Schema:
#   tags(tagID, name)
#   itemTags(itemID, tagID, type) -- type is usually 0 or 1, we'll use 0 (user tag)

echo "Injecting variant tags..."

python3 << 'PYEOF'
import sqlite3

db_path = "/home/ga/Zotero/zotero.sqlite"
conn = sqlite3.connect(db_path)
c = conn.cursor()

# Helper to add tag
def ensure_tag(name):
    c.execute("SELECT tagID FROM tags WHERE name=?", (name,))
    row = c.fetchone()
    if row:
        return row[0]
    c.execute("INSERT INTO tags (name) VALUES (?)", (name,))
    return c.lastrowid

# Helper to get item ID by partial title
def get_item_id(title_part):
    c.execute("""
        SELECT i.itemID FROM items i
        JOIN itemData d ON i.itemID=d.itemID
        JOIN itemDataValues v ON d.valueID=v.valueID
        WHERE d.fieldID=1 AND v.value LIKE ?
        LIMIT 1
    """, (f"%{title_part}%",))
    row = c.fetchone()
    return row[0] if row else None

# Helper to tag item
def tag_item(title_part, tag_name):
    tid = ensure_tag(tag_name)
    iid = get_item_id(title_part)
    if iid and tid:
        # Check if already tagged to avoid constraint errors
        c.execute("SELECT * FROM itemTags WHERE itemID=? AND tagID=?", (iid, tid))
        if not c.fetchone():
            c.execute("INSERT INTO itemTags (itemID, tagID, type) VALUES (?, ?, 0)", (iid, tid))
            print(f"Tagged '{title_part}' with '{tag_name}'")
    else:
        print(f"Warning: Could not tag '{title_part}' with '{tag_name}' (Item or Tag missing)")

# 1. Setup Canonical 'Deep Learning' (2 items)
tag_item("Deep Learning", "Deep Learning") # LeCun
tag_item("ImageNet Classification", "Deep Learning")

# 2. Setup Variant 'deep-learning' (2 items)
tag_item("Attention Is All You Need", "deep-learning")
tag_item("BERT:", "deep-learning")

# 3. Setup Variant 'deep learning' (lowercase) (2 items)
tag_item("Deep Residual Learning", "deep learning")
tag_item("Generative Adversarial Nets", "deep learning")

# 4. Setup Canonical 'NLP' (1 item)
tag_item("A Mathematical Theory of Communication", "NLP")

# 5. Setup Variant 'nlp' (3 items)
tag_item("Language Models are Few-Shot", "nlp")
tag_item("Computing Machinery and Intelligence", "nlp")
tag_item("Recursive Functions", "nlp")

conn.commit()
conn.close()
PYEOF

# Record setup timestamp
date +%s > /tmp/task_start_time

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
sleep 5

# Maximize and focus
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="