#!/bin/bash
set -e
echo "=== Setting up standardize_page_hyphens task ==="

DB_PATH="/home/ga/Zotero/zotero.sqlite"

# 1. Stop Zotero to safely modify DB
echo "Stopping Zotero..."
pkill -9 -f zotero 2>/dev/null || true
sleep 3

# 2. Seed the library with standard data
echo "Seeding library..."
# We use 'all' mode to ensure we have the classic and ML papers
python3 /workspace/scripts/seed_library.py --mode all > /dev/null

# 3. Corrupt the data (introduce bad hyphens)
echo "Corrupting page numbers..."
python3 << 'EOF'
import sqlite3
import sys

db_path = "/home/ga/Zotero/zotero.sqlite"

# Target modifications
# Turing: double hyphen
# Shannon: en-dash (u2013)
# He: double hyphen
targets = [
    ("On Computable Numbers", "230--265"),
    ("A Mathematical Theory of Communication", "379\u2013423"),
    ("Deep Residual Learning", "770--778")
]

try:
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()

    # Field ID 1 is Title, Field ID 32 is Pages (standard Zotero schema)
    # We need to find the valueID for the pages field of the item with the matching title
    
    for title_frag, new_pages in targets:
        print(f"Modifying '{title_frag}' to '{new_pages}'...")
        
        # 1. Find item ID
        cur.execute("""
            SELECT i.itemID 
            FROM items i
            JOIN itemData d ON i.itemID = d.itemID
            JOIN itemDataValues v ON d.valueID = v.valueID
            WHERE d.fieldID = 1 AND v.value LIKE ?
        """, (f"%{title_frag}%",))
        
        row = cur.fetchone()
        if not row:
            print(f"Error: Item '{title_frag}' not found!")
            continue
            
        item_id = row[0]
        
        # 2. Find the valueID for the Pages field (fieldID=32) for this item
        cur.execute("""
            SELECT d.valueID 
            FROM itemData d 
            WHERE d.itemID = ? AND d.fieldID = 32
        """, (item_id,))
        
        val_row = cur.fetchone()
        
        if val_row:
            # Update existing value
            val_id = val_row[0]
            # Note: In a real scenario, multiple items might share a valueID, 
            # but for this setup it's acceptable to update the value directly 
            # as these are specific unique page ranges.
            cur.execute("UPDATE itemDataValues SET value = ? WHERE valueID = ?", (new_pages, val_id))
        else:
            # Insert new value if pages field didn't exist (unlikely for these seeded papers, but safe)
            # Create new value
            cur.execute("INSERT INTO itemDataValues (value) VALUES (?)", (new_pages,))
            new_val_id = cur.lastrowid
            # Link to item
            cur.execute("INSERT INTO itemData (itemID, fieldID, valueID) VALUES (?, 32, ?)", (item_id, new_val_id))
            
    conn.commit()
    conn.close()
    print("Database modification complete.")

except Exception as e:
    print(f"Error modifying database: {e}")
    sys.exit(1)
EOF

# 4. Start Zotero
echo "Starting Zotero..."
# Using setsid and nohup pattern from templates to ensure it persists
sudo -u ga bash -c 'DISPLAY=:1 setsid /opt/zotero/zotero --no-remote > /home/ga/zotero.log 2>&1 &'

# 5. Wait for window
echo "Waiting for Zotero window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Zotero"; then
        echo "Zotero window detected"
        break
    fi
    sleep 1
done

# 6. Maximize and focus
sleep 2
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true

# 7. Record start time
date +%s > /tmp/task_start_time.txt

# 8. Initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="