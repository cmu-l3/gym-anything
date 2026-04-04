#!/bin/bash
# Setup for migrate_tags_to_collections task
# Seeds library and applies specific tags to specific papers

echo "=== Setting up migrate_tags_to_collections task ==="

DB="/home/ga/Zotero/zotero.sqlite"

# ── 1. Stop Zotero ───────────────────────────────────────────────────────────
echo "Stopping Zotero..."
pkill -9 -f zotero 2>/dev/null || true
sleep 3

# ── 2. Seed papers ───────────────────────────────────────────────────────────
echo "Seeding library..."
python3 /workspace/scripts/seed_library.py --mode all > /tmp/seed_output.txt 2>/tmp/seed_stderr.txt
if [ $? -ne 0 ]; then
    echo "ERROR: seeding failed"
    cat /tmp/seed_stderr.txt
    exit 1
fi

# ── 3. Apply Tags Programmatically ───────────────────────────────────────────
# We use python to handle the SQL logic for finding IDs and inserting tags safely
python3 << 'PYEOF'
import sqlite3

db_path = "/home/ga/Zotero/zotero.sqlite"
conn = sqlite3.connect(db_path)
cur = conn.cursor()

# Define the mapping of tags to paper titles
tag_map = {
    "dataset-mnist": [
        "Deep Learning", 
        "Generative Adversarial Nets"
    ],
    "dataset-imagenet": [
        "ImageNet Classification with Deep Convolutional Neural Networks",
        "Deep Residual Learning for Image Recognition"
    ]
}

# Track IDs for verification later
expected_ids = {
    "dataset-mnist": [],
    "dataset-imagenet": []
}

try:
    for tag_name, titles in tag_map.items():
        # 1. Ensure tag exists or get its ID
        cur.execute("SELECT tagID FROM tags WHERE name=?", (tag_name,))
        row = cur.fetchone()
        if row:
            tag_id = row[0]
        else:
            cur.execute("INSERT INTO tags (name) VALUES (?)", (tag_name,))
            tag_id = cur.lastrowid
        
        print(f"Tag '{tag_name}' has ID {tag_id}")

        for title in titles:
            # 2. Find item ID
            # Zotero 7 schema: items -> itemData -> itemDataValues
            cur.execute("""
                SELECT i.itemID FROM items i 
                JOIN itemData d ON i.itemID=d.itemID 
                JOIN itemDataValues v ON d.valueID=v.valueID 
                WHERE d.fieldID=1 AND v.value LIKE ?
            """, (f"%{title}%",))
            
            item_row = cur.fetchone()
            if item_row:
                item_id = item_row[0]
                expected_ids[tag_name].append(item_id)
                
                # 3. Link tag to item
                # Check if already linked
                cur.execute("SELECT * FROM itemTags WHERE itemID=? AND tagID=?", (item_id, tag_id))
                if not cur.fetchone():
                    # type=0 is standard manual tag
                    cur.execute("INSERT INTO itemTags (itemID, tagID, type) VALUES (?, ?, 0)", (item_id, tag_id))
                    print(f"  Tagged item {item_id} ('{title}') with '{tag_name}'")
            else:
                print(f"  WARNING: Could not find paper '{title}'")

    conn.commit()
    
    # Save expected IDs for the export script to use
    import json
    with open("/tmp/expected_migration_ids.json", "w") as f:
        json.dump(expected_ids, f)

except Exception as e:
    print(f"SQL Error: {e}")
    conn.rollback()
finally:
    conn.close()
PYEOF

# ── 4. Restart Zotero ────────────────────────────────────────────────────────
echo "Restarting Zotero..."
# Using setsid to detach from shell so it persists
sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid /opt/zotero/zotero --no-remote > /dev/null 2>&1 &"

echo "Waiting for Zotero window..."
for i in $(seq 1 60); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "zotero"; then
        echo "  Window found after ${i}s"
        break
    fi
    sleep 1
done

# Ensure window is ready
sleep 5
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# ── 5. Record Initial State ──────────────────────────────────────────────────
# Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

# Timestamp
date +%s > /tmp/task_start_time.txt

echo "=== Setup Complete: migrate_tags_to_collections ==="