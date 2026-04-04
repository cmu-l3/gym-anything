#!/bin/bash
echo "=== Setting up migrate_misplaced_dois task ==="

DB="/home/ga/Zotero/zotero.sqlite"

# 1. Stop Zotero to modify DB safely
echo "Stopping Zotero..."
pkill -9 -f zotero 2>/dev/null || true
sleep 3

# 2. Seed library with base data
echo "Seeding library..."
python3 /workspace/scripts/seed_library.py --mode all > /dev/null 2>&1

# 3. Corrupt the data (Move DOIs to Extra)
# We use a python script to handle the SQLite logic cleanly
python3 << 'PYEOF'
import sqlite3

db_path = "/home/ga/Zotero/zotero.sqlite"
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

# Get field IDs
cursor.execute("SELECT fieldID FROM fields WHERE fieldName='DOI'")
res = cursor.fetchone()
doi_field_id = res[0] if res else 59  # Default to 59 if query fails

cursor.execute("SELECT fieldID FROM fields WHERE fieldName='extra'")
res = cursor.fetchone()
extra_field_id = res[0] if res else 26 # Default to 26

targets = [
    {
        "title": "Attention Is All You Need", 
        "doi": "10.5555/3295222.3295349"
    },
    {
        "title": "Deep Learning", 
        "doi": "10.1038/nature14539"
    },
    {
        "title": "ImageNet Classification with Deep Convolutional Neural Networks", 
        "doi": "10.5555/2999134.2999257"
    }
]

print(f"Modifying database (DOI field: {doi_field_id}, Extra field: {extra_field_id})...")

for t in targets:
    # 1. Find Item ID
    cursor.execute("""
        SELECT i.itemID 
        FROM items i 
        JOIN itemData d ON i.itemID=d.itemID 
        JOIN itemDataValues v ON d.valueID=v.valueID 
        WHERE d.fieldID=1 AND v.value=?
    """, (t['title'],))
    
    row = cursor.fetchone()
    if row:
        item_id = row[0]
        print(f"Found '{t['title']}' at itemID {item_id}")
        
        # 2. Remove existing DOI (if any)
        # Find valueID for DOI field linked to this item
        cursor.execute("SELECT valueID FROM itemData WHERE itemID=? AND fieldID=?", (item_id, doi_field_id))
        doi_rows = cursor.fetchall()
        for r in doi_rows:
            # Delete from itemData
            cursor.execute("DELETE FROM itemData WHERE itemID=? AND fieldID=?", (item_id, doi_field_id))
            # Note: We leave itemDataValues orphan, Zotero cleans them up or ignores them
            
        # 3. Add/Update Extra field with "DOI: <value>"
        extra_text = f"DOI: {t['doi']}"
        
        # Check if value exists in itemDataValues
        cursor.execute("SELECT valueID FROM itemDataValues WHERE value=?", (extra_text,))
        val_row = cursor.fetchone()
        
        if val_row:
            extra_value_id = val_row[0]
        else:
            cursor.execute("INSERT INTO itemDataValues (value) VALUES (?)", (extra_text,))
            extra_value_id = cursor.lastrowid
            
        # Check if item already has 'extra' field in itemData
        cursor.execute("SELECT valueID FROM itemData WHERE itemID=? AND fieldID=?", (item_id, extra_field_id))
        existing_extra = cursor.fetchone()
        
        if existing_extra:
            # Update mapping
            cursor.execute("UPDATE itemData SET valueID=? WHERE itemID=? AND fieldID=?", (extra_value_id, item_id, extra_field_id))
        else:
            # Insert mapping
            cursor.execute("INSERT INTO itemData (itemID, fieldID, valueID) VALUES (?, ?, ?)", (item_id, extra_field_id, extra_value_id))
            
        # Update modification time
        cursor.execute("UPDATE items SET dateModified=datetime('now') WHERE itemID=?", (item_id,))
        
    else:
        print(f"WARNING: Could not find paper '{t['title']}'")

conn.commit()
conn.close()
PYEOF

# 4. Restart Zotero to load changes
echo "Restarting Zotero..."
sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid /opt/zotero/zotero --no-remote > /dev/null 2>&1 &"

# 5. Wait for window
echo "Waiting for Zotero window..."
for i in $(seq 1 45); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "zotero"; then
        echo "Zotero window found"
        break
    fi
    sleep 1
done

# 6. Maximize
sleep 3
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true

# 7. Record Timestamp
date +%s > /tmp/task_start_time.txt

# 8. Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="