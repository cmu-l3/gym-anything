#!/bin/bash

echo "=== Setting up citation_audit_repair task ==="
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
import sqlite3, sys, random, string, os
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

cases = [
    # WRONG REPORTER (3 cases)
    {
        "caseName": "Mapp v. Ohio",
        "court": "United States Supreme Court",
        "reporter": "F.3d",
        "reporterVolume": "367",
        "firstPage": "643",
        "dateDecided": "1961",
        "abstractNote": "Held that evidence obtained in violation of the Fourth Amendment is inadmissible in state courts, extending the exclusionary rule."
    },
    {
        "caseName": "United States v. Leon",
        "court": "United States Supreme Court",
        "reporter": "F.2d",
        "reporterVolume": "468",
        "firstPage": "897",
        "dateDecided": "1984",
        "abstractNote": "Established the good faith exception to the exclusionary rule for searches made in objectively reasonable reliance on a defective warrant."
    },
    {
        "caseName": "Weeks v. United States",
        "court": "United States Supreme Court",
        "reporter": "F.2d",
        "reporterVolume": "232",
        "firstPage": "383",
        "dateDecided": "1914",
        "abstractNote": "Established the exclusionary rule for federal courts, barring evidence obtained through unconstitutional searches and seizures."
    },
    # WRONG COURT (2 cases)
    {
        "caseName": "Illinois v. Gates",
        "court": "USDC N.D. Ill.",
        "reporter": "U.S.",
        "reporterVolume": "462",
        "firstPage": "213",
        "dateDecided": "1983",
        "abstractNote": "Replaced the two-pronged Aguilar-Spinelli test with a totality-of-the-circumstances approach to determine probable cause for search warrants."
    },
    {
        "caseName": "Bivens v. Six Unknown Named Agents of Federal Bureau of Narcotics",
        "court": "USDC E.D.N.Y.",
        "reporter": "U.S.",
        "reporterVolume": "403",
        "firstPage": "388",
        "dateDecided": "1971",
        "abstractNote": "Recognized an implied cause of action for damages against federal officers who violate constitutional rights."
    },
    # WRONG YEAR (1 case)
    {
        "caseName": "United States v. Cortez",
        "court": "United States Supreme Court",
        "reporter": "U.S.",
        "reporterVolume": "449",
        "firstPage": "411",
        "dateDecided": "2001",
        "abstractNote": "Established the totality of circumstances standard for determining reasonable suspicion for investigatory stops."
    },
    # WRONG FIRST PAGE (2 cases)
    {
        "caseName": "Terry v. Ohio",
        "court": "United States Supreme Court",
        "reporter": "U.S.",
        "reporterVolume": "392",
        "firstPage": "999",
        "dateDecided": "1968",
        "abstractNote": "Held that police may stop and briefly detain a person based on reasonable articulable suspicion of criminal activity."
    },
    {
        "caseName": "Katz v. United States",
        "court": "United States Supreme Court",
        "reporter": "U.S.",
        "reporterVolume": "389",
        "firstPage": "999",
        "dateDecided": "1967",
        "abstractNote": "Established the reasonable expectation of privacy standard, holding that the Fourth Amendment protects people, not just places."
    },
    # CORRECT (2 control cases)
    {
        "caseName": "Florida v. Riley",
        "court": "United States Supreme Court",
        "reporter": "U.S.",
        "reporterVolume": "488",
        "firstPage": "445",
        "dateDecided": "1989",
        "abstractNote": "Held that police observation of a greenhouse from a helicopter at 400 feet does not require a warrant under the Fourth Amendment."
    },
    {
        "caseName": "Carpenter v. United States",
        "court": "United States Supreme Court",
        "reporter": "U.S.",
        "reporterVolume": "585",
        "firstPage": "296",
        "dateDecided": "2018",
        "abstractNote": "Held that obtaining cell-site location information constitutes a Fourth Amendment search requiring a warrant."
    },
]

for i, case in enumerate(cases):
    item_id = insert_case(conn, case, offset_hours=i)
    print(f"Inserted: {case['caseName']} (itemID={item_id})")

conn.close()
print("All 10 cases inserted successfully.")
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
DISPLAY=:1 scrot /tmp/citation_audit_repair_start.png 2>/dev/null || true
echo "Start screenshot saved to /tmp/citation_audit_repair_start.png"

echo "=== Setup Complete ==="
