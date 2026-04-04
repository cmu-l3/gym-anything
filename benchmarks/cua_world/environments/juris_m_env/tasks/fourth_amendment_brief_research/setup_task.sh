#!/bin/bash

echo "=== Setting up fourth_amendment_brief_research task ==="
source /workspace/scripts/task_utils.sh 2>/dev/null || true

JURISM_DB=""
for db_candidate in /home/ga/Jurism/jurism.sqlite /home/ga/Jurism/zotero.sqlite; do
    if [ -f "$db_candidate" ]; then JURISM_DB="$db_candidate"; break; fi
done

if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Jurism database not found"
    exit 1
fi

echo "Using database: $JURISM_DB"

# Kill Jurism so database is not locked during setup
pkill -f "/opt/jurism/jurism" 2>/dev/null || true
sleep 3
echo "Jurism stopped for database setup"

python3 << 'PYEOF'
import sqlite3, sys, random, string, os, json
from datetime import datetime, timedelta

JURISM_DB = ""
for db_candidate in ["/home/ga/Jurism/jurism.sqlite", "/home/ga/Jurism/zotero.sqlite"]:
    if os.path.exists(db_candidate):
        JURISM_DB = db_candidate
        break

if not JURISM_DB:
    print("ERROR: Jurism database not found")
    sys.exit(1)

conn = sqlite3.connect(JURISM_DB)
c = conn.cursor()

# Clear existing user library items
c.execute("DELETE FROM itemCreators WHERE itemID IN (SELECT itemID FROM items WHERE libraryID=1 AND itemTypeID NOT IN (1,3,31))")
c.execute("DELETE FROM itemData WHERE itemID IN (SELECT itemID FROM items WHERE libraryID=1 AND itemTypeID NOT IN (1,3,31))")
c.execute("DELETE FROM collectionItems WHERE itemID IN (SELECT itemID FROM items WHERE libraryID=1 AND itemTypeID NOT IN (1,3,31))")
c.execute("DELETE FROM itemTags WHERE itemID IN (SELECT itemID FROM items WHERE libraryID=1)")
c.execute("DELETE FROM tags WHERE tagID IN (SELECT tagID FROM itemTags WHERE itemID IN (SELECT itemID FROM items WHERE libraryID=1))")
c.execute("DELETE FROM collectionItems")
c.execute("DELETE FROM collections WHERE libraryID=1")
c.execute("DELETE FROM items WHERE libraryID=1 AND itemTypeID NOT IN (1,3,31)")
c.execute("DELETE FROM itemDataValues WHERE valueID NOT IN (SELECT valueID FROM itemData)")
c.execute("DELETE FROM settings WHERE setting='db' AND key='integrityCheck'")
conn.commit()

FIELD = {
    'caseName': 58,
    'court': 60,
    'reporter': 49,
    'reporterVolume': 66,
    'firstPage': 67,
    'dateDecided': 69,
    'abstractNote': 2
}

def rand_key():
    return ''.join(random.choices(string.ascii_uppercase + string.digits, k=8))

def get_or_create_value(conn, value):
    c = conn.cursor()
    c.execute("SELECT valueID FROM itemDataValues WHERE value=?", (value,))
    r = c.fetchone()
    if r:
        return r[0]
    c.execute("INSERT INTO itemDataValues (value) VALUES (?)", (value,))
    return c.lastrowid

def insert_case(conn, fields, offset_hours=0):
    c = conn.cursor()
    now = (datetime.now() - timedelta(hours=offset_hours)).strftime("%Y-%m-%d %H:%M:%S")
    key = rand_key()
    c.execute(
        "INSERT INTO items (itemTypeID, dateAdded, dateModified, clientDateModified, libraryID, key) VALUES (?,?,?,?,1,?)",
        (9, now, now, now, key)
    )
    item_id = c.lastrowid
    for fname, value in fields.items():
        if value is None:
            continue
        fid = FIELD.get(fname)
        if fid is None:
            continue
        vid = get_or_create_value(conn, str(value))
        c.execute("INSERT OR IGNORE INTO itemData (itemID, fieldID, valueID) VALUES (?,?,?)", (item_id, fid, vid))
    conn.commit()
    return item_id

# Seed only 2 pre-existing items (not Fourth Amendment related)
preexisting = [
    {
        "caseName": "Marbury v. Madison",
        "court": "United States Supreme Court",
        "reporter": "U.S.",
        "reporterVolume": "5",
        "firstPage": "137",
        "dateDecided": "1803",
        "abstractNote": "Established the principle of judicial review, allowing courts to invalidate laws that conflict with the Constitution."
    },
    {
        "caseName": "Brown v. Board of Education",
        "court": "United States Supreme Court",
        "reporter": "U.S.",
        "reporterVolume": "347",
        "firstPage": "483",
        "dateDecided": "1954",
        "abstractNote": "Held that racial segregation in public schools is unconstitutional, overturning Plessy v. Ferguson."
    },
]

preexisting_ids = []
for i, case in enumerate(preexisting):
    item_id = insert_case(conn, case, offset_hours=i)
    preexisting_ids.append(item_id)
    print(f"Inserted pre-existing: {case['caseName']} (itemID={item_id})")

# Save preexisting IDs for verifier reference
setup_meta = {
    "preexisting_item_ids": preexisting_ids,
    "preexisting_case_names": [c["caseName"] for c in preexisting]
}
meta_path = "/tmp/fourth_amendment_brief_setup_meta.json"
with open(meta_path, "w") as f:
    json.dump(setup_meta, f, indent=2)
print(f"Setup metadata written to {meta_path}")

conn.close()
print("Pre-existing items inserted. Library ready for agent.")
PYEOF

echo "Python seeding complete (exit code: $?)"

# Relaunch Jurism so the agent can interact with it via the GUI
echo "Relaunching Jurism..."
setsid sudo -u ga bash -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus DISPLAY=:1 /opt/jurism/jurism --no-remote >> /home/ga/jurism.log 2>&1 &'
sleep 5

# Wait for Jurism to load and dismiss any in-app alert dialogs
if type wait_and_dismiss_jurism_alerts &>/dev/null; then
    wait_and_dismiss_jurism_alerts 45
fi

# Maximize and focus Jurism window
DISPLAY=:1 wmctrl -r "Jurism" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Jurism" 2>/dev/null || true
sleep 1

# Take start screenshot
DISPLAY=:1 scrot /tmp/fourth_amendment_brief_start.png 2>/dev/null || true
echo "Start screenshot saved to /tmp/fourth_amendment_brief_start.png"

echo "=== Setup Complete ==="
