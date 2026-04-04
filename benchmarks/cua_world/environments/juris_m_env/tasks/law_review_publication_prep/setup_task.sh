#!/bin/bash
echo "=== Setting up law_review_publication_prep task ==="

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

# Stop Jurism to allow DB access
echo "Stopping Jurism for DB operations..."
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# Clear existing library data and seed fresh items
echo "Seeding Juris-M library with 15 items (8 articles + 7 cases)..."
python3 << 'PYEOF'
import sqlite3, sys, random, string, os
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

# Clear existing library data
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
print("Library cleared.")

FIELD_CASE = {'caseName':58,'court':60,'reporter':49,'reporterVolume':66,'firstPage':67,'dateDecided':69,'abstractNote':2}
FIELD_ARTICLE = {'title':1,'abstractNote':2,'publicationTitle':7,'date':8,'volume':22,'pages':47,'issue':72,'ISSN':108}

def rand_key():
    return ''.join(random.choices(string.ascii_uppercase + string.digits, k=8))

def get_or_create_value(conn, value):
    c = conn.cursor()
    c.execute("SELECT valueID FROM itemDataValues WHERE value=?", (value,))
    r = c.fetchone()
    if r: return r[0]
    c.execute("INSERT INTO itemDataValues (value) VALUES (?)", (value,))
    return c.lastrowid

def insert_case(conn, fields, offset_hours=0):
    c = conn.cursor()
    now = (datetime.now() - timedelta(hours=offset_hours)).strftime("%Y-%m-%d %H:%M:%S")
    key = rand_key()
    c.execute("INSERT INTO items (itemTypeID, dateAdded, dateModified, clientDateModified, libraryID, key) VALUES (?,?,?,?,1,?)", (9, now, now, now, key))
    item_id = c.lastrowid
    for fname, val in fields.items():
        if val is None: continue
        fid = FIELD_CASE.get(fname)
        if fid is None: continue
        vid = get_or_create_value(conn, str(val))
        c.execute("INSERT OR IGNORE INTO itemData (itemID, fieldID, valueID) VALUES (?,?,?)", (item_id, fid, vid))
    conn.commit()
    return item_id

def insert_article(conn, fields, offset_hours=0):
    c = conn.cursor()
    now = (datetime.now() - timedelta(hours=offset_hours)).strftime("%Y-%m-%d %H:%M:%S")
    key = rand_key()
    c.execute("INSERT INTO items (itemTypeID, dateAdded, dateModified, clientDateModified, libraryID, key) VALUES (?,?,?,?,1,?)", (24, now, now, now, key))
    item_id = c.lastrowid
    for fname, val in fields.items():
        if fname in ('authorFirst','authorLast') or val is None: continue
        fid = FIELD_ARTICLE.get(fname)
        if fid is None: continue
        vid = get_or_create_value(conn, str(val))
        c.execute("INSERT OR IGNORE INTO itemData (itemID, fieldID, valueID) VALUES (?,?,?)", (item_id, fid, vid))
    # Creator
    if fields.get('authorFirst') and fields.get('authorLast'):
        c.execute("SELECT creatorID FROM creators WHERE firstName=? AND lastName=?", (fields['authorFirst'], fields['authorLast']))
        r = c.fetchone()
        if r: creator_id = r[0]
        else:
            c.execute("INSERT INTO creators (firstName, lastName, fieldMode) VALUES (?,?,0)", (fields['authorFirst'], fields['authorLast']))
            creator_id = c.lastrowid
        c.execute("INSERT OR IGNORE INTO itemCreators (itemID, creatorID, creatorTypeID, orderIndex) VALUES (?,?,1,0)", (item_id, creator_id))
    conn.commit()
    return item_id

# 8 Law Review Articles
articles = [
    # NO abstract (4 items)
    {
        "title": "A Taxonomy of Privacy",
        "authorFirst": "Daniel J.",
        "authorLast": "Solove",
        "publicationTitle": "University of Pennsylvania Law Review",
        "date": "2006",
        "volume": "154",
        "pages": "477-560",
        "issue": None,
        "ISSN": "0041-9907",
        "abstractNote": None
    },
    {
        "title": "Lex Informatica: The Formulation of Information Policy Rules Through Technology",
        "authorFirst": "Joel R.",
        "authorLast": "Reidenberg",
        "publicationTitle": "Texas Law Review",
        "date": "1998",
        "volume": "76",
        "pages": "553-594",
        "issue": None,
        "ISSN": "0040-4411",
        "abstractNote": None
    },
    {
        "title": "Broken Promises of Privacy: Responding to the Surprising Failure of Anonymization",
        "authorFirst": "Paul",
        "authorLast": "Ohm",
        "publicationTitle": "UCLA Law Review",
        "date": "2010",
        "volume": "57",
        "pages": "1701-1777",
        "issue": None,
        "ISSN": "0041-5650",
        "abstractNote": None
    },
    {
        "title": "Big Data Ethics",
        "authorFirst": "Neil M.",
        "authorLast": "Richards",
        "publicationTitle": "Wake Forest Law Review",
        "date": "2014",
        "volume": "49",
        "pages": "393-432",
        "issue": None,
        "ISSN": "0043-003X",
        "abstractNote": None
    },
    # HAS abstract (4 items)
    {
        "title": "A History of Online Gatekeeping",
        "authorFirst": "Jonathan",
        "authorLast": "Zittrain",
        "publicationTitle": "Harvard Journal of Law & Technology",
        "date": "2006",
        "volume": "19",
        "pages": "253-298",
        "issue": None,
        "ISSN": "0897-3393",
        "abstractNote": "Examines the historical evolution of online gatekeepers — entities that control access to internet content — and the implications for freedom of speech and expression online."
    },
    {
        "title": "The Fourth Amendment and New Technologies: Constitutional Myths and the Case for Caution",
        "authorFirst": "Orin S.",
        "authorLast": "Kerr",
        "publicationTitle": "Michigan Law Review",
        "date": "2004",
        "volume": "102",
        "pages": "801-888",
        "issue": None,
        "ISSN": "0026-2234",
        "abstractNote": "Analyzes how courts should apply Fourth Amendment doctrine to new technologies, arguing for a cautious approach that maintains constitutional principles across technological change."
    },
    {
        "title": "The PII Problem: Privacy and a New Concept of Personally Identifiable Information",
        "authorFirst": "Paul M.",
        "authorLast": "Schwartz",
        "publicationTitle": "New York University Law Review",
        "date": "2011",
        "volume": "86",
        "pages": "1814-1894",
        "issue": None,
        "ISSN": "0028-7881",
        "abstractNote": "Proposes a risk-based model for defining personally identifiable information in privacy law, replacing the traditional binary approach with a contextual framework."
    },
    {
        "title": "Privacy on the Books and on the Ground",
        "authorFirst": "Kenneth A.",
        "authorLast": "Bamberger",
        "publicationTitle": "Stanford Law Review",
        "date": "2011",
        "volume": "63",
        "pages": "247-315",
        "issue": None,
        "ISSN": "0038-9765",
        "abstractNote": "Explores the gap between formal legal privacy requirements and actual organizational privacy practices, drawing on empirical research with privacy officers across industries."
    },
]

# 7 Court Cases
cases = [
    {
        "caseName": "Carpenter v. United States",
        "court": "United States Supreme Court",
        "reporter": "U.S.",
        "reporterVolume": "585",
        "firstPage": "296",
        "dateDecided": "2018",
        "abstractNote": "Held that the government's acquisition of cell-site location information constitutes a Fourth Amendment search requiring a warrant."
    },
    {
        "caseName": "Kyllo v. United States",
        "court": "United States Supreme Court",
        "reporter": "U.S.",
        "reporterVolume": "533",
        "firstPage": "27",
        "dateDecided": "2001",
        "abstractNote": "Held that using a thermal imaging device to detect heat emanating from a private home constitutes a Fourth Amendment search."
    },
    {
        "caseName": "Riley v. California",
        "court": "United States Supreme Court",
        "reporter": "U.S.",
        "reporterVolume": "573",
        "firstPage": "373",
        "dateDecided": "2014",
        "abstractNote": "Held that police generally must obtain a warrant before searching a cell phone seized incident to arrest."
    },
    {
        "caseName": "United States v. Jones",
        "court": "United States Supreme Court",
        "reporter": "U.S.",
        "reporterVolume": "565",
        "firstPage": "400",
        "dateDecided": "2012",
        "abstractNote": "Held that attaching a GPS tracking device to a vehicle and monitoring its movements constitutes a Fourth Amendment search."
    },
    {
        "caseName": "Katz v. United States",
        "court": "United States Supreme Court",
        "reporter": "U.S.",
        "reporterVolume": "389",
        "firstPage": "347",
        "dateDecided": "1967",
        "abstractNote": "Established the reasonable expectation of privacy standard for Fourth Amendment protection."
    },
    {
        "caseName": "In re NSA Telecommunications Records Litigation",
        "court": "United States Court of Appeals for the Ninth Circuit",
        "reporter": "F.3d",
        "reporterVolume": "671",
        "firstPage": "881",
        "dateDecided": "2011",
        "abstractNote": "Addressed constitutional and statutory challenges to the NSA's bulk collection of telephone metadata under the USA PATRIOT Act."
    },
    {
        "caseName": "ACLU v. Clapper",
        "court": "United States Court of Appeals for the Second Circuit",
        "reporter": "F.3d",
        "reporterVolume": "785",
        "firstPage": "787",
        "dateDecided": "2015",
        "abstractNote": "Held that the NSA's bulk telephone metadata collection program exceeded the authority granted by Section 215 of the PATRIOT Act."
    },
]

inserted_articles = 0
inserted_cases = 0

for i, art in enumerate(articles):
    try:
        item_id = insert_article(conn, art, offset_hours=i)
        print(f"  Inserted article: {art['title'][:60]}")
        inserted_articles += 1
    except Exception as e:
        print(f"  ERROR inserting article {art['title'][:40]}: {e}", file=sys.stderr)

for i, case in enumerate(cases):
    try:
        item_id = insert_case(conn, case, offset_hours=i)
        print(f"  Inserted case: {case['caseName']}")
        inserted_cases += 1
    except Exception as e:
        print(f"  ERROR inserting case {case['caseName']}: {e}", file=sys.stderr)

conn.close()
print(f"Seeding complete: {inserted_articles} articles, {inserted_cases} cases inserted.")
PYEOF

echo "=== DB seeding complete ==="

# Verify item count
ITEM_COUNT=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM items WHERE libraryID=1 AND itemTypeID NOT IN (1,3,31)" 2>/dev/null || echo "unknown")
echo "Total items in library: $ITEM_COUNT"

# Record task start timestamp
date +%s > /tmp/law_review_task_start_timestamp

# Relaunch Jurism
echo "Relaunching Jurism..."
setsid sudo -u ga bash -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus DISPLAY=:1 /opt/jurism/jurism --no-remote >> /home/ga/jurism.log 2>&1 &'
sleep 8

# Wait for Jurism to load and dismiss any in-app alert dialogs
if declare -f wait_and_dismiss_jurism_alerts > /dev/null 2>&1; then
    wait_and_dismiss_jurism_alerts 45
else
    sleep 10
fi

# Maximize and focus Jurism window
DISPLAY=:1 wmctrl -r "Jurism" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Jurism" 2>/dev/null || true
sleep 1

# Take screenshot to verify state
DISPLAY=:1 import -window root /tmp/law_review_task_start.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/law_review_task_start.png 2>/dev/null || true

echo "=== law_review_publication_prep task setup complete ==="
echo "Library contains $ITEM_COUNT items ready for organization."
