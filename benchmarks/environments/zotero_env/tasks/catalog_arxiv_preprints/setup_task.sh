#!/bin/bash
# Setup for catalog_arxiv_preprints task
# Ensures target papers exist and cleans their metadata fields

echo "=== Setting up catalog_arxiv_preprints task ==="

DB="/home/ga/Zotero/zotero.sqlite"

# 1. Stop Zotero to modify DB safely
echo "Stopping Zotero..."
pkill -9 -f zotero 2>/dev/null || true
sleep 3

# 2. Seed papers (Using mode 'all' includes the ML papers needed)
echo "Seeding library..."
python3 /workspace/scripts/seed_library.py --mode all > /tmp/seed_log.txt 2>&1
if [ $? -ne 0 ]; then
    echo "ERROR: seed_library.py failed"
    cat /tmp/seed_log.txt
    exit 1
fi

# 3. Clean the target fields (Library Catalog and Call Number) for the specific papers
# This ensures the agent must actually enter the data
echo "Cleaning target metadata fields..."
python3 << 'PYEOF'
import sqlite3

db_path = "/home/ga/Zotero/zotero.sqlite"
targets = [
    "Attention Is All You Need",
    "BERT: Pre-training of Deep Bidirectional",
    "Generative Adversarial Nets"
]

try:
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    
    # Get field IDs for 'libraryCatalog' and 'callNumber'
    cur.execute("SELECT fieldID FROM fields WHERE fieldName='libraryCatalog'")
    res = cur.fetchone()
    cat_field_id = res[0] if res else 24
    
    cur.execute("SELECT fieldID FROM fields WHERE fieldName='callNumber'")
    res = cur.fetchone()
    call_field_id = res[0] if res else 25
    
    print(f"Field IDs - Catalog: {cat_field_id}, Call Number: {call_field_id}")

    for title in targets:
        # Find item ID
        cur.execute("""
            SELECT items.itemID FROM items 
            JOIN itemData ON items.itemID = itemData.itemID 
            JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
            WHERE itemData.fieldID = 1 AND itemDataValues.value LIKE ?
        """, (f"%{title}%",))
        
        row = cur.fetchone()
        if row:
            item_id = row[0]
            print(f"Cleaning metadata for item {item_id} ('{title}')...")
            
            # Delete existing data for these fields for this item
            cur.execute("DELETE FROM itemData WHERE itemID=? AND fieldID=?", (item_id, cat_field_id))
            cur.execute("DELETE FROM itemData WHERE itemID=? AND fieldID=?", (item_id, call_field_id))
        else:
            print(f"WARNING: Target paper '{title}' not found during setup!")
            
    conn.commit()
    conn.close()
    print("Database preparation complete.")
except Exception as e:
    print(f"Error preparing database: {e}")
    exit(1)
PYEOF

# 4. Record task start time
date +%s > /tmp/task_start_time.txt

# 5. Restart Zotero
echo "Restarting Zotero..."
sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid /opt/zotero/zotero --no-remote > /home/ga/zotero.log 2>&1 &"

# Wait for window
echo "Waiting for Zotero window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Zotero"; then
        echo "Window found."
        break
    fi
    sleep 1
done

# Maximize and focus
sleep 2
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true

# 6. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="