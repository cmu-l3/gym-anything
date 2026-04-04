#!/bin/bash
# Setup for normalize_journal_names task
# Seeds library and deliberately abbreviates 5 journal names

echo "=== Setting up normalize_journal_names task ==="

DB="/home/ga/Zotero/zotero.sqlite"

# 1. Stop Zotero to modify DB safely
echo "Stopping Zotero..."
pkill -9 -f zotero 2>/dev/null || true
sleep 3

# 2. Seed library with standard papers
echo "Seeding library..."
python3 /workspace/scripts/seed_library.py --mode all > /dev/null 2>&1

# 3. Abbreviate journal names via Python/SQLite
# We use Python for cleaner SQL parameter handling
echo "Abbreviating journal names..."
python3 << 'PYEOF'
import sqlite3
import os

db_path = "/home/ga/Zotero/zotero.sqlite"

# Map: Title keyword -> Abbreviated Journal Name
modifications = {
    "Minimum-Redundancy Codes": "Proc. IRE",
    "Recursive Functions": "Commun. ACM",
    "Connexion with Graphs": "Numer. Math.",
    "Mathematical Theory of Communication": "Bell Syst. Tech. J.",
    "Elementary Number Theory": "Am. J. Math."
}

try:
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    for title_part, abbr_journal in modifications.items():
        # 1. Find the item ID for the paper
        cursor.execute("""
            SELECT i.itemID 
            FROM items i
            JOIN itemData d ON i.itemID = d.itemID 
            JOIN itemDataValues v ON d.valueID = v.valueID
            WHERE d.fieldID = 1 AND v.value LIKE ?
        """, (f"%{title_part}%",))
        
        row = cursor.fetchone()
        if not row:
            print(f"Warning: Paper not found for '{title_part}'")
            continue
            
        item_id = row[0]
        
        # 2. Find the valueID for the Publication Title field (fieldID=38 in Zotero 7)
        # Note: We assume the field exists (seeded papers have it). 
        # If not, we'd need to insert, but seeding guarantees it.
        cursor.execute("""
            SELECT d.valueID 
            FROM itemData d
            WHERE d.itemID = ? AND d.fieldID = 38
        """, (item_id,))
        
        val_row = cursor.fetchone()
        if not val_row:
            print(f"Warning: No publication field for item {item_id}")
            continue
            
        old_value_id = val_row[0]
        
        # 3. Create or get valueID for the new abbreviated string
        # Zotero shares value strings. We check if the abbr string exists.
        cursor.execute("SELECT valueID FROM itemDataValues WHERE value = ?", (abbr_journal,))
        val_exists = cursor.fetchone()
        
        if val_exists:
            new_value_id = val_exists[0]
        else:
            cursor.execute("INSERT INTO itemDataValues (value) VALUES (?)", (abbr_journal,))
            new_value_id = cursor.lastrowid
            
        # 4. Update the itemData to point to the new valueID
        cursor.execute("""
            UPDATE itemData 
            SET valueID = ? 
            WHERE itemID = ? AND fieldID = 38
        """, (new_value_id, item_id))
        
        print(f"Updated item {item_id} ('{title_part}') to journal '{abbr_journal}'")

    conn.commit()
    conn.close()
    print("Database updates complete.")

except Exception as e:
    print(f"Error updating database: {e}")
    exit(1)
PYEOF

# Record timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 4. Restart Zotero
echo "Restarting Zotero..."
# Using setsid to detach properly
sudo -u ga bash -c "DISPLAY=:1 setsid /opt/zotero/zotero --no-remote > /home/ga/zotero.log 2>&1 &"

# Wait for window
echo "Waiting for Zotero window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "zotero"; then
        echo "Zotero window detected"
        break
    fi
    sleep 1
done

# Maximize and focus
sleep 2
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true

# Capture initial state screenshot
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="