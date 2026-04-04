#!/bin/bash
echo "=== Setting up comparative_law_organization task ==="
source /workspace/scripts/task_utils.sh

# Find Jurism database
JURISM_DB=""
for db_candidate in /home/ga/Jurism/jurism.sqlite /home/ga/Jurism/zotero.sqlite; do
    if [ -f "$db_candidate" ]; then
        JURISM_DB="$db_candidate"
        break
    fi
done

if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    exit 1
fi

echo "Using database: $JURISM_DB"

# Stop Jurism to allow DB access (DB is locked while Jurism runs)
echo "Stopping Jurism for DB operations..."
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# Seed the database with 12 cases using Python heredoc
python3 << 'PYEOF'
import sqlite3
import random
import string
import sys
import os
from datetime import datetime, timedelta

JURISM_DB = ""
for db_candidate in ["/home/ga/Jurism/jurism.sqlite", "/home/ga/Jurism/zotero.sqlite"]:
    if os.path.exists(db_candidate):
        JURISM_DB = db_candidate
        break

if not JURISM_DB:
    print("ERROR: Cannot find Jurism database", file=sys.stderr)
    sys.exit(1)

conn = sqlite3.connect(JURISM_DB)
c = conn.cursor()

# ---- Clear all user items, collections, tags ----
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
print("Database cleared successfully.")

# ---- Helper functions ----
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
    """Insert a case item. fields is a dict with keys matching FIELD names. Use None for missing fields."""
    FIELD = {
        'caseName': 58,
        'court': 60,
        'reporter': 49,
        'reporterVolume': 66,
        'firstPage': 67,
        'dateDecided': 69,
        'abstractNote': 2,
    }
    c = conn.cursor()
    now = (datetime.now() - timedelta(hours=offset_hours)).strftime("%Y-%m-%d %H:%M:%S")
    key = rand_key()
    c.execute(
        "INSERT INTO items (itemTypeID, dateAdded, dateModified, clientDateModified, libraryID, key) VALUES (?,?,?,?,1,?)",
        (9, now, now, now, key)
    )
    item_id = c.lastrowid
    for field_name, value in fields.items():
        if value is None:
            continue
        fid = FIELD.get(field_name)
        if fid is None:
            continue
        vid = get_or_create_value(conn, str(value))
        c.execute(
            "INSERT OR IGNORE INTO itemData (itemID, fieldID, valueID) VALUES (?,?,?)",
            (item_id, fid, vid)
        )
    conn.commit()
    return item_id

# ---- Seed the 12 cases with intentional errors ----
cases = [
    # US Cases: 3 missing court, 1 wrong court, 1 correct
    {
        "caseName": "Brown v. Board of Education",
        "court": None,  # INTENTIONALLY MISSING
        "reporter": "U.S.",
        "reporterVolume": "347",
        "firstPage": "483",
        "dateDecided": "1954",
        "abstractNote": "Landmark case declaring racial segregation in public schools unconstitutional, overturning Plessy v. Ferguson.",
    },
    {
        "caseName": "Miranda v. Arizona",
        "court": None,  # INTENTIONALLY MISSING
        "reporter": "U.S.",
        "reporterVolume": "384",
        "firstPage": "436",
        "dateDecided": "1966",
        "abstractNote": "Established Miranda warning requirements for suspects in police custody.",
    },
    {
        "caseName": "New York Times Co. v. Sullivan",
        "court": "Unknown Court",  # INTENTIONALLY WRONG
        "reporter": "U.S.",
        "reporterVolume": "376",
        "firstPage": "254",
        "dateDecided": "1964",
        "abstractNote": "Established the actual malice standard for defamation claims by public officials.",
    },
    {
        "caseName": "Obergefell v. Hodges",
        "court": "United States Supreme Court",  # CORRECT
        "reporter": "U.S.",
        "reporterVolume": "576",
        "firstPage": "644",
        "dateDecided": "2015",
        "abstractNote": "Held that the fundamental right to marry is guaranteed to same-sex couples.",
    },
    {
        "caseName": "Gideon v. Wainwright",
        "court": None,  # INTENTIONALLY MISSING
        "reporter": "U.S.",
        "reporterVolume": "372",
        "firstPage": "335",
        "dateDecided": "1963",
        "abstractNote": "Held that the Sixth Amendment right to counsel applies to state criminal proceedings.",
    },
    # UK Cases: 1 wrong court, 3 correct
    {
        "caseName": "Donoghue v Stevenson",
        "court": "House of Lords",  # CORRECT
        "reporter": "AC",
        "reporterVolume": "1932",
        "firstPage": "562",
        "dateDecided": "1932",
        "abstractNote": "Foundational negligence case establishing the neighbour principle in tort law.",
    },
    {
        "caseName": "R v Brown",
        "court": "Unknown Court",  # INTENTIONALLY WRONG
        "reporter": "All ER",
        "reporterVolume": "1993",
        "firstPage": "75",
        "dateDecided": "1993",
        "abstractNote": "House of Lords case on consent as a defence to assault occasioning actual bodily harm.",
    },
    {
        "caseName": "Entick v Carrington",
        "court": "Court of Common Pleas",  # CORRECT
        "reporter": "St Tr",
        "reporterVolume": "19",
        "firstPage": "1030",
        "dateDecided": "1765",
        "abstractNote": "Established that government searches and seizures require lawful authority.",
    },
    {
        "caseName": "R v Secretary of State for the Home Department ex p Simms",
        "court": "House of Lords",  # CORRECT
        "reporter": "AC",
        "reporterVolume": "2000",
        "firstPage": "115",
        "dateDecided": "2000",
        "abstractNote": "Important case on freedom of expression for prisoners in the United Kingdom.",
    },
    # Canada Cases: all correct
    {
        "caseName": "R v Oakes",
        "court": "Supreme Court of Canada",  # CORRECT
        "reporter": "SCR",
        "reporterVolume": "1",
        "firstPage": "103",
        "dateDecided": "1986",
        "abstractNote": "Established the Oakes test for justifying limitations on Charter rights under section 1.",
    },
    {
        "caseName": "Vriend v Alberta",
        "court": "Supreme Court of Canada",  # CORRECT
        "reporter": "SCR",
        "reporterVolume": "1",
        "firstPage": "493",
        "dateDecided": "1998",
        "abstractNote": "Extended Charter equality rights protection to sexual orientation.",
    },
    {
        "caseName": "Carter v Canada (Attorney General)",
        "court": "Supreme Court of Canada",  # CORRECT
        "reporter": "SCR",
        "reporterVolume": "1",
        "firstPage": "331",
        "dateDecided": "2015",
        "abstractNote": "Struck down the Criminal Code prohibition on physician-assisted dying as unconstitutional.",
    },
]

inserted = 0
for i, case_fields in enumerate(cases):
    item_id = insert_case(conn, case_fields, offset_hours=i)
    print(f"  Inserted: {case_fields['caseName']} (itemID={item_id}, court={case_fields.get('court')})")
    inserted += 1

conn.close()
print(f"\nSuccessfully inserted {inserted} cases into Jurism database.")
PYEOF

echo "Python seeding complete (exit code: $?)"

# Record baseline timestamp and initial item count
date +%s > /tmp/task_start_timestamp
INITIAL_COUNT=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM items WHERE libraryID=1 AND itemTypeID NOT IN (1,3,31)" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/comparative_law_initial_count
echo "Initial item count: $INITIAL_COUNT"

# Relaunch Jurism
echo "Relaunching Jurism..."
setsid sudo -u ga bash -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus DISPLAY=:1 /opt/jurism/jurism --no-remote >> /home/ga/jurism.log 2>&1 &'
sleep 5

# Wait for Jurism to load and dismiss any in-app alert dialogs
wait_and_dismiss_jurism_alerts 45

# Maximize and focus Jurism window
DISPLAY=:1 wmctrl -r "Jurism" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Jurism" 2>/dev/null || true
sleep 1

# Take screenshot to verify start state
take_screenshot /tmp/comparative_law_start.png
echo "Start screenshot saved to /tmp/comparative_law_start.png"

echo "=== Task setup complete ==="
echo "Library seeded with $INITIAL_COUNT cases (12 expected)"
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"
