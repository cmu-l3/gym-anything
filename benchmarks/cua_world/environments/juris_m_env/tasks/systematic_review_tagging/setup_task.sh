#!/bin/bash
echo "=== Setting up systematic_review_tagging task ==="
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

# Seed the database with 14 cases using Python heredoc
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

def add_tag(conn, item_id, tag_name):
    c = conn.cursor()
    c.execute("SELECT tagID FROM tags WHERE name=?", (tag_name,))
    r = c.fetchone()
    if r:
        tag_id = r[0]
    else:
        c.execute("INSERT INTO tags (name) VALUES (?)", (tag_name,))
        tag_id = c.lastrowid
    c.execute("INSERT OR IGNORE INTO itemTags (itemID, tagID, type) VALUES (?,?,0)", (item_id, tag_id))
    conn.commit()

# ---- Free speech cases with intentionally inconsistent tags ----
free_speech_cases = [
    {
        "caseName": "Tinker v. Des Moines Independent Community School District",
        "court": "United States Supreme Court",
        "reporter": "U.S.",
        "reporterVolume": "393",
        "firstPage": "503",
        "dateDecided": "1969",
        "abstractNote": "Held that students do not shed their First Amendment rights at the schoolhouse gate, protecting student political expression.",
        "tag": "First Amendment",
    },
    {
        "caseName": "New York Times Co. v. Sullivan",
        "court": "United States Supreme Court",
        "reporter": "U.S.",
        "reporterVolume": "376",
        "firstPage": "254",
        "dateDecided": "1964",
        "abstractNote": "Established the actual malice standard required for public officials to prevail in defamation suits.",
        "tag": "expression",
    },
    {
        "caseName": "Brandenburg v. Ohio",
        "court": "United States Supreme Court",
        "reporter": "U.S.",
        "reporterVolume": "395",
        "firstPage": "444",
        "dateDecided": "1969",
        "abstractNote": "Held that the government cannot punish inflammatory speech unless it is directed to inciting imminent lawless action and likely to produce such action.",
        "tag": "free speech",
    },
    {
        "caseName": "Schenck v. United States",
        "court": "United States Supreme Court",
        "reporter": "U.S.",
        "reporterVolume": "249",
        "firstPage": "47",
        "dateDecided": "1919",
        "abstractNote": "Upheld the Espionage Act conviction of a Socialist Party official for distributing anti-draft leaflets, introducing the clear and present danger test.",
        "tag": "First Amendment",
    },
    {
        "caseName": "Texas v. Johnson",
        "court": "United States Supreme Court",
        "reporter": "U.S.",
        "reporterVolume": "491",
        "firstPage": "397",
        "dateDecided": "1989",
        "abstractNote": "Held that burning the American flag as political protest is protected symbolic speech under the First Amendment.",
        "tag": None,  # No tag intentionally
    },
    {
        "caseName": "Chaplinsky v. New Hampshire",
        "court": "United States Supreme Court",
        "reporter": "U.S.",
        "reporterVolume": "315",
        "firstPage": "568",
        "dateDecided": "1942",
        "abstractNote": "Articulated the fighting words doctrine, holding that certain words which by their very utterance inflict injury or tend to incite immediate breach of the peace are not protected by the First Amendment.",
        "tag": "free-speech",  # Already correct
    },
    {
        "caseName": "R.A.V. v. City of St. Paul",
        "court": "United States Supreme Court",
        "reporter": "U.S.",
        "reporterVolume": "505",
        "firstPage": "377",
        "dateDecided": "1992",
        "abstractNote": "Struck down a bias-motivated crime ordinance as an unconstitutional content-based restriction on speech, even though the speech involved fighting words.",
        "tag": "hate speech",
    },
    {
        "caseName": "Morse v. Frederick",
        "court": "United States Supreme Court",
        "reporter": "U.S.",
        "reporterVolume": "551",
        "firstPage": "393",
        "dateDecided": "2007",
        "abstractNote": "Held that school officials can restrict student speech that is reasonably viewed as promoting illegal drug use.",
        "tag": None,  # No tag intentionally
    },
    {
        "caseName": "Bethel School District No. 403 v. Fraser",
        "court": "United States Supreme Court",
        "reporter": "U.S.",
        "reporterVolume": "478",
        "firstPage": "675",
        "dateDecided": "1986",
        "abstractNote": "Held that schools may discipline students for lewd and obscene speech at a school-sponsored event.",
        "tag": None,  # No tag intentionally
    },
]

# ---- Unrelated cases ----
unrelated_cases = [
    {
        "caseName": "Marbury v. Madison",
        "court": "United States Supreme Court",
        "reporter": "U.S.",
        "reporterVolume": "5",
        "firstPage": "137",
        "dateDecided": "1803",
        "abstractNote": "Established the principle of judicial review in the United States.",
        "tag": "constitutional",
    },
    {
        "caseName": "Brown v. Board of Education",
        "court": "United States Supreme Court",
        "reporter": "U.S.",
        "reporterVolume": "347",
        "firstPage": "483",
        "dateDecided": "1954",
        "abstractNote": "Declared racial segregation in public schools unconstitutional.",
        "tag": None,  # No tag intentionally
    },
    {
        "caseName": "Miranda v. Arizona",
        "court": "United States Supreme Court",
        "reporter": "U.S.",
        "reporterVolume": "384",
        "firstPage": "436",
        "dateDecided": "1966",
        "abstractNote": "Established the Miranda warning requirement for suspects in police custody.",
        "tag": "Fifth Amendment",
    },
    {
        "caseName": "Gideon v. Wainwright",
        "court": "United States Supreme Court",
        "reporter": "U.S.",
        "reporterVolume": "372",
        "firstPage": "335",
        "dateDecided": "1963",
        "abstractNote": "Held that the Sixth Amendment right to counsel applies to state criminal proceedings.",
        "tag": "Sixth Amendment",
    },
    {
        "caseName": "Palsgraf v. Long Island Railroad Co.",
        "court": "New York Court of Appeals",
        "reporter": "N.Y.",
        "reporterVolume": "248",
        "firstPage": "339",
        "dateDecided": "1928",
        "abstractNote": "Landmark negligence case establishing the foreseeability test for proximate cause in tort law.",
        "tag": None,  # No tag intentionally
    },
]

all_cases = free_speech_cases + unrelated_cases
inserted = 0
for i, case_fields in enumerate(all_cases):
    tag = case_fields.pop("tag", None)
    item_id = insert_case(conn, case_fields, offset_hours=i)
    if tag:
        add_tag(conn, item_id, tag)
    print(f"  Inserted: {case_fields['caseName']} (itemID={item_id}, tag={tag})")
    inserted += 1

conn.close()
print(f"\nSuccessfully inserted {inserted} cases into Jurism database.")
PYEOF

echo "Python seeding complete (exit code: $?)"

# Record baseline timestamp and initial item count
date +%s > /tmp/task_start_timestamp
INITIAL_COUNT=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM items WHERE libraryID=1 AND itemTypeID NOT IN (1,3,31)" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/systematic_review_initial_count
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
take_screenshot /tmp/systematic_review_start.png
echo "Start screenshot saved to /tmp/systematic_review_start.png"

echo "=== Task setup complete ==="
echo "Library seeded with $INITIAL_COUNT cases (14 expected)"
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"
