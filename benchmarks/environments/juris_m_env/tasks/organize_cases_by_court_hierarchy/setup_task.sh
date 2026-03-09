#!/bin/bash
set -e
echo "=== Setting up task: organize_cases_by_court_hierarchy ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Identify Database
DB_PATH=$(get_jurism_db)
if [ -z "$DB_PATH" ]; then
    # Fallback search if utils fail
    DB_PATH=$(find /home/ga -name jurism.sqlite | head -n 1)
fi

if [ -z "$DB_PATH" ]; then
    echo "ERROR: Jurism DB not found"
    exit 1
fi

echo "Using database: $DB_PATH"

# 2. Stop Jurism for safe DB access
pkill -f jurism || true
sleep 3

# 3. Create Python injection script for specific cases (Alcoa & Palsgraf)
# We also ensure the standard cases (Brown, Miranda, Gideon) exist via the standard injector if needed
cat > /tmp/inject_courts.py << 'EOF'
import sys
import sqlite3
import os
import random
import string
from datetime import datetime

# Path to standard injector
sys.path.append('/workspace/utils')
try:
    import inject_references
except ImportError:
    # Fallback mock if utils missing (should not happen in env)
    print("Warning: inject_references not found")
    inject_references = None

def get_or_create_value(conn, value):
    cursor = conn.cursor()
    cursor.execute("SELECT valueID FROM itemDataValues WHERE value = ?", (value,))
    row = cursor.fetchone()
    if row: return row[0]
    cursor.execute("INSERT INTO itemDataValues (value) VALUES (?)", (value,))
    return cursor.lastrowid

def insert_case(conn, case_data):
    cursor = conn.cursor()
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    
    # 1. Create Item
    key = ''.join(random.choices(string.ascii_uppercase + string.digits, k=8))
    # itemTypeID 9 = Case
    cursor.execute(
        "INSERT INTO items (itemTypeID, dateAdded, dateModified, clientDateModified, libraryID, key) VALUES (9, ?, ?, ?, 1, ?)",
        (now, now, now, key)
    )
    item_id = cursor.lastrowid
    
    # 2. Add Data
    # Mappings for Jurism 6 (based on inject_references.py)
    fields = {
        58: case_data['caseName'],       # caseName
        60: case_data['court'],          # court
        69: case_data['dateDecided'],    # dateDecided
        49: case_data.get('reporter'),   # reporter
        66: case_data.get('volume'),     # reporterVolume
        67: case_data.get('page'),       # firstPage
        2:  case_data.get('abstract')    # abstractNote
    }
    
    for field_id, value in fields.items():
        if value:
            val_id = get_or_create_value(conn, str(value))
            cursor.execute("INSERT INTO itemData (itemID, fieldID, valueID) VALUES (?, ?, ?)", (item_id, field_id, val_id))
            
    return item_id

def main(db_path):
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    # 1. Clean up existing collections to ensure fresh start
    print("Clearing existing collections...")
    cursor.execute("DELETE FROM collectionItems")
    cursor.execute("DELETE FROM collections")
    
    # 2. Define required cases
    required_cases = [
        {
            "caseName": "United States v. Aluminum Co. of America",
            "court": "United States Court of Appeals for the Second Circuit",
            "dateDecided": "1945",
            "reporter": "F.2d",
            "volume": "148",
            "page": "416",
            "abstract": "Antitrust case regarding monopoly power."
        },
        {
            "caseName": "Palsgraf v. Long Island Railroad Co.",
            "court": "Court of Appeals of New York",
            "dateDecided": "1928",
            "reporter": "N.Y.",
            "volume": "248",
            "page": "339",
            "abstract": "Tort law case establishing proximate cause."
        }
    ]
    
    # 3. Insert if not present
    for case in required_cases:
        # Check by name (field 58)
        cursor.execute("""
            SELECT items.itemID FROM items 
            JOIN itemData ON items.itemID = itemData.itemID 
            JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
            WHERE fieldID=58 AND value = ?
        """, (case['caseName'],))
        
        if not cursor.fetchone():
            print(f"Injecting: {case['caseName']}")
            insert_case(conn, case)
        else:
            print(f"Exists: {case['caseName']}")

    conn.commit()
    conn.close()

if __name__ == "__main__":
    main(sys.argv[1])
EOF

# 4. Run injection
echo "Injecting Circuit and State cases..."
python3 /tmp/inject_courts.py "$DB_PATH"

# 5. Ensure standard references exist (Brown, Miranda, Gideon)
# The utility script handles checking if they exist
python3 /workspace/utils/inject_references.py "$DB_PATH"

# 6. Restart Jurism
echo "Restarting Jurism..."
setsid sudo -u ga bash -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus DISPLAY=:1 /opt/jurism/jurism --no-remote > /home/ga/jurism.log 2>&1 &'
sleep 5

# Wait for window
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Jurism"; then
        break
    fi
    sleep 1
done

# Dismiss any startup alerts (common in Jurism)
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Return 2>/dev/null || true

# Maximize and focus
DISPLAY=:1 wmctrl -r "Jurism" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Jurism" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="