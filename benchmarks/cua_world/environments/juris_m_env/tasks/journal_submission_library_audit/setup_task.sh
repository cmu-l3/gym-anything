#!/bin/bash
echo "=== Setting up journal_submission_library_audit task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Find Jurism database
JURISM_DB=""
for db_candidate in /home/ga/Jurism/jurism.sqlite /home/ga/Jurism/zotero.sqlite; do
    if [ -f "$db_candidate" ]; then
        JURISM_DB="$db_candidate"
        break
    fi
done

if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Jurism database not found"
    exit 1
fi

echo "Using database: $JURISM_DB"

# Stop Jurism to allow DB access
echo "Stopping Jurism for DB operations..."
pkill -f "/opt/jurism/jurism" 2>/dev/null || true
sleep 3
echo "Jurism stopped for database setup"

# Delete stale outputs BEFORE recording timestamp
rm -f /tmp/journal_submission_library_audit_result.json 2>/dev/null || true
rm -f /home/ga/Documents/symposium_bibliography.ris 2>/dev/null || true

# Record task start timestamp
date +%s > /tmp/journal_submission_task_start_timestamp

# Clear and seed the database with 18 items (11 cases + 7 articles) with planted errors
echo "Seeding Juris-M library with 18 items..."
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
c.execute("DELETE FROM itemRelations")
c.execute("DELETE FROM itemCreators WHERE itemID IN (SELECT itemID FROM items WHERE libraryID=1 AND itemTypeID NOT IN (1,3,31))")
c.execute("DELETE FROM itemData WHERE itemID IN (SELECT itemID FROM items WHERE libraryID=1 AND itemTypeID NOT IN (1,3,31))")
c.execute("DELETE FROM collectionItems WHERE itemID IN (SELECT itemID FROM items WHERE libraryID=1 AND itemTypeID NOT IN (1,3,31))")
c.execute("DELETE FROM itemTags WHERE itemID IN (SELECT itemID FROM items WHERE libraryID=1)")
c.execute("DELETE FROM tags WHERE tagID NOT IN (SELECT tagID FROM itemTags)")
c.execute("DELETE FROM collectionItems")
c.execute("DELETE FROM collections WHERE libraryID=1")
c.execute("DELETE FROM items WHERE libraryID=1 AND itemTypeID NOT IN (1,3,31)")
c.execute("DELETE FROM itemDataValues WHERE valueID NOT IN (SELECT valueID FROM itemData)")
c.execute("DELETE FROM settings WHERE setting='db' AND key='integrityCheck'")
conn.commit()
print("Library cleared.")

# Field ID mappings (verified against Jurism 6.0.30m3)
FIELD_CASE = {
    'caseName': 58,
    'court': 60,
    'reporter': 49,
    'reporterVolume': 66,
    'firstPage': 67,
    'dateDecided': 69,
    'abstractNote': 2,
}

FIELD_ARTICLE = {
    'title': 1,
    'abstractNote': 2,
    'publicationTitle': 7,
    'date': 8,
    'volume': 22,
    'pages': 47,
    'issue': 72,
    'ISSN': 108,
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
        fid = FIELD_CASE.get(fname)
        if fid is None:
            continue
        vid = get_or_create_value(conn, str(value))
        c.execute("INSERT OR IGNORE INTO itemData (itemID, fieldID, valueID) VALUES (?,?,?)", (item_id, fid, vid))
    conn.commit()
    return item_id

def insert_article(conn, fields, offset_hours=0):
    c = conn.cursor()
    now = (datetime.now() - timedelta(hours=offset_hours)).strftime("%Y-%m-%d %H:%M:%S")
    key = rand_key()
    c.execute(
        "INSERT INTO items (itemTypeID, dateAdded, dateModified, clientDateModified, libraryID, key) VALUES (?,?,?,?,1,?)",
        (24, now, now, now, key)
    )
    item_id = c.lastrowid
    for fname, val in fields.items():
        if fname in ('authorFirst', 'authorLast') or val is None:
            continue
        fid = FIELD_ARTICLE.get(fname)
        if fid is None:
            continue
        vid = get_or_create_value(conn, str(val))
        c.execute("INSERT OR IGNORE INTO itemData (itemID, fieldID, valueID) VALUES (?,?,?)", (item_id, fid, vid))
    # Creator
    if fields.get('authorFirst') and fields.get('authorLast'):
        c.execute("SELECT creatorID FROM creators WHERE firstName=? AND lastName=?",
                  (fields['authorFirst'], fields['authorLast']))
        r = c.fetchone()
        if r:
            creator_id = r[0]
        else:
            c.execute("INSERT INTO creators (firstName, lastName, fieldMode) VALUES (?,?,0)",
                      (fields['authorFirst'], fields['authorLast']))
            creator_id = c.lastrowid
        c.execute("INSERT OR IGNORE INTO itemCreators (itemID, creatorID, creatorTypeID, orderIndex) VALUES (?,?,1,0)",
                  (item_id, creator_id))
    conn.commit()
    return item_id

# ============================================================
# 11 Supreme Court Cases
# Errors: 3 wrong reporters, 2 wrong dates, 3 missing courts, 1 wrong firstPage
# ============================================================
cases = [
    # MISSING COURT (3 cases) - court field left empty
    {
        "caseName": "Mapp v. Ohio",
        "court": None,  # ERROR: should be "United States Supreme Court"
        "reporter": "U.S.",
        "reporterVolume": "367",
        "firstPage": "643",
        "dateDecided": "1961-06-19",
        "abstractNote": "Held that evidence obtained in violation of the Fourth Amendment is inadmissible in state courts through the Fourteenth Amendment, extending the exclusionary rule to all courts."
    },
    {
        "caseName": "Smith v. Maryland",
        "court": None,  # ERROR: should be "United States Supreme Court"
        "reporter": "U.S.",
        "reporterVolume": "442",
        "firstPage": "735",
        "dateDecided": "1979-06-20",
        "abstractNote": "Held that the installation and use of a pen register by the telephone company at police request was not a search under the Fourth Amendment because the caller had no reasonable expectation of privacy in numbers dialed."
    },
    {
        "caseName": "Kyllo v. United States",
        "court": None,  # ERROR: should be "United States Supreme Court"
        "reporter": "U.S.",
        "reporterVolume": "533",
        "firstPage": "27",
        "dateDecided": "2001-06-11",
        "abstractNote": "Held that use of a thermal imaging device aimed at a private home from a public street to detect relative amounts of heat constitutes a Fourth Amendment search requiring a warrant."
    },
    # WRONG REPORTER (3 cases) - F.2d or F.3d instead of U.S.
    {
        "caseName": "Katz v. United States",
        "court": "United States Supreme Court",
        "reporter": "F.2d",  # ERROR: should be "U.S."
        "reporterVolume": "389",
        "firstPage": "347",
        "dateDecided": "1967-12-18",
        "abstractNote": "Established the reasonable expectation of privacy test, holding that the Fourth Amendment protects people, not places, and that a wiretap on a public phone booth constituted a search."
    },
    {
        "caseName": "United States v. Miller",
        "court": "United States Supreme Court",
        "reporter": "F.3d",  # ERROR: should be "U.S."
        "reporterVolume": "425",
        "firstPage": "435",
        "dateDecided": "1976-04-21",
        "abstractNote": "Held that bank records are not protected by the Fourth Amendment because customers have no reasonable expectation of privacy in information voluntarily conveyed to third parties."
    },
    {
        "caseName": "Florida v. Jardines",
        "court": "United States Supreme Court",
        "reporter": "F.2d",  # ERROR: should be "U.S."
        "reporterVolume": "569",
        "firstPage": "1",
        "dateDecided": "2013-03-26",
        "abstractNote": "Held that using a drug-sniffing dog on the porch of a suspected marijuana grower constituted an unlicensed physical intrusion and therefore a Fourth Amendment search."
    },
    # WRONG DATE (2 cases) - 100 years in the future
    {
        "caseName": "Terry v. Ohio",
        "court": "United States Supreme Court",
        "reporter": "U.S.",
        "reporterVolume": "392",
        "firstPage": "1",
        "dateDecided": "2068-06-10",  # ERROR: should be "1968-06-10"
        "abstractNote": "Held that police may briefly detain and frisk a person based on reasonable articulable suspicion of criminal activity, establishing the stop-and-frisk doctrine."
    },
    {
        "caseName": "Riley v. California",
        "court": "United States Supreme Court",
        "reporter": "U.S.",
        "reporterVolume": "573",
        "firstPage": "373",
        "dateDecided": "2114-06-25",  # ERROR: should be "2014-06-25"
        "abstractNote": "Held unanimously that police generally must obtain a warrant before searching digital information on a cell phone seized incident to arrest."
    },
    # WRONG FIRST PAGE (1 case)
    {
        "caseName": "Illinois v. Gates",
        "court": "United States Supreme Court",
        "reporter": "U.S.",
        "reporterVolume": "462",
        "firstPage": "999",  # ERROR: should be "213"
        "dateDecided": "1983-06-08",
        "abstractNote": "Replaced the two-pronged Aguilar-Spinelli test with a totality-of-the-circumstances approach for evaluating whether an informant's tip establishes probable cause."
    },
    # CORRECT (2 control cases)
    {
        "caseName": "United States v. Jones",
        "court": "United States Supreme Court",
        "reporter": "U.S.",
        "reporterVolume": "565",
        "firstPage": "400",
        "dateDecided": "2012-01-23",
        "abstractNote": "Held that attaching a GPS tracking device to a vehicle and using it to monitor movements constitutes a Fourth Amendment search under the trespass theory."
    },
    {
        "caseName": "Carpenter v. United States",
        "court": "United States Supreme Court",
        "reporter": "U.S.",
        "reporterVolume": "585",
        "firstPage": "296",
        "dateDecided": "2018-06-22",
        "abstractNote": "Held that the government's acquisition of historical cell-site location information constitutes a Fourth Amendment search, requiring a warrant supported by probable cause."
    },
]

# ============================================================
# 7 Law Review Articles
# Errors: 2 wrong volumes, 1 wrong date, 1 wrong pages
# ============================================================
articles = [
    # WRONG VOLUME (2 articles) - leading digit(s) dropped
    {
        "title": "A Taxonomy of Privacy",
        "authorFirst": "Daniel J.",
        "authorLast": "Solove",
        "publicationTitle": "University of Pennsylvania Law Review",
        "date": "2006",
        "volume": "54",  # ERROR: should be "154"
        "pages": "477-564",
        "issue": None,
        "ISSN": "0041-9907",
        "abstractNote": "Develops a taxonomy of privacy harms organized into four groups: information collection, information processing, information dissemination, and invasion, providing a framework for understanding the multiplicity of privacy violations."
    },
    {
        "title": "Broken Promises of Privacy: Responding to the Surprising Failure of Anonymization",
        "authorFirst": "Paul",
        "authorLast": "Ohm",
        "publicationTitle": "UCLA Law Review",
        "date": "2010",
        "volume": "5",  # ERROR: should be "57"
        "pages": "1701-1777",
        "issue": None,
        "ISSN": "0041-5650",
        "abstractNote": "Argues that computer scientists have demonstrated that anonymization of data is far more fragile than policymakers have assumed, and proposes a new regulatory framework based on this reality."
    },
    # WRONG DATE (1 article) - 100 years in the future
    {
        "title": "Cell Phone Location Data and the Fourth Amendment: A Question of Law, Not Fact",
        "authorFirst": "Susan",
        "authorLast": "Freiwald",
        "publicationTitle": "Maryland Law Review",
        "date": "2111",  # ERROR: should be "2011"
        "volume": "70",
        "pages": "681-753",
        "issue": None,
        "ISSN": "0025-4282",
        "abstractNote": "Analyzes the legal framework governing law enforcement access to cell phone location data, arguing that such access should require a warrant based on probable cause."
    },
    # WRONG PAGES (1 article) - truncated
    {
        "title": "Beyond the (Current) Fourth Amendment: Protecting Third-Party Information, Third Parties, and the Rest of Us Too",
        "authorFirst": "Stephen E.",
        "authorLast": "Henderson",
        "publicationTitle": "Pepperdine Law Review",
        "date": "2007",
        "volume": "34",
        "pages": "97",  # ERROR: should be "975-1036"
        "issue": None,
        "ISSN": "0092-430X",
        "abstractNote": "Proposes extending Fourth Amendment protection beyond the current third-party doctrine to encompass information held by third parties, arguing the doctrine is outdated in the digital age."
    },
    # CORRECT (3 control articles)
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
        "abstractNote": "Analyzes how courts should apply Fourth Amendment doctrine to new surveillance technologies, arguing for a cautious, case-by-case approach rather than sweeping doctrinal change."
    },
    {
        "title": "Knowledge and Fourth Amendment Privacy",
        "authorFirst": "Matthew",
        "authorLast": "Tokson",
        "publicationTitle": "Northwestern University Law Review",
        "date": "2016",
        "volume": "111",
        "pages": "139-210",
        "issue": None,
        "ISSN": "0029-3571",
        "abstractNote": "Examines the role of knowledge in Fourth Amendment privacy analysis, proposing a framework that accounts for what individuals actually know about surveillance practices."
    },
    {
        "title": "The Case Against the Case for Third-Party Doctrine: A Response to Epstein and Kerr",
        "authorFirst": "Erin",
        "authorLast": "Murphy",
        "publicationTitle": "Berkeley Technology Law Journal",
        "date": "2009",
        "volume": "24",
        "pages": "1239-1253",
        "issue": None,
        "ISSN": "1086-3818",
        "abstractNote": "Responds to defenses of the third-party doctrine, arguing that the doctrine's foundations are weaker than its proponents claim and that it should be substantially narrowed or abandoned."
    },
]

# Insert all cases
inserted_cases = 0
for i, case in enumerate(cases):
    try:
        item_id = insert_case(conn, case, offset_hours=i)
        print(f"  Inserted case: {case['caseName']} (itemID={item_id})")
        inserted_cases += 1
    except Exception as e:
        print(f"  ERROR inserting case {case['caseName']}: {e}", file=sys.stderr)

# Insert all articles
inserted_articles = 0
for i, art in enumerate(articles):
    try:
        item_id = insert_article(conn, art, offset_hours=i + len(cases))
        print(f"  Inserted article: {art['title'][:60]} (itemID={item_id})")
        inserted_articles += 1
    except Exception as e:
        print(f"  ERROR inserting article {art['title'][:40]}: {e}", file=sys.stderr)

conn.close()
print(f"Seeding complete: {inserted_cases} cases, {inserted_articles} articles inserted.")
PYEOF

echo "Python seeding complete (exit code: $?)"

# Verify item count
ITEM_COUNT=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM items WHERE libraryID=1 AND itemTypeID NOT IN (1,3,31)" 2>/dev/null || echo "unknown")
echo "Total items in library: $ITEM_COUNT"

# Write the reference CSV file for the agent to consult
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/correct_citations.csv << 'CSVEOF'
type,name,reporter,reporter_volume,first_page,date,court,publication,volume,pages
case,Mapp v. Ohio,U.S.,367,643,1961-06-19,United States Supreme Court,,,
case,Katz v. United States,U.S.,389,347,1967-12-18,United States Supreme Court,,,
case,Terry v. Ohio,U.S.,392,1,1968-06-10,United States Supreme Court,,,
case,United States v. Miller,U.S.,425,435,1976-04-21,United States Supreme Court,,,
case,Smith v. Maryland,U.S.,442,735,1979-06-20,United States Supreme Court,,,
case,Illinois v. Gates,U.S.,462,213,1983-06-08,United States Supreme Court,,,
case,Kyllo v. United States,U.S.,533,27,2001-06-11,United States Supreme Court,,,
case,United States v. Jones,U.S.,565,400,2012-01-23,United States Supreme Court,,,
case,Florida v. Jardines,U.S.,569,1,2013-03-26,United States Supreme Court,,,
case,Riley v. California,U.S.,573,373,2014-06-25,United States Supreme Court,,,
case,Carpenter v. United States,U.S.,585,296,2018-06-22,United States Supreme Court,,,
article,A Taxonomy of Privacy,,,,2006,,University of Pennsylvania Law Review,154,477-564
article,The Fourth Amendment and New Technologies,,,,2004,,Michigan Law Review,102,801-888
article,Broken Promises of Privacy,,,,2010,,UCLA Law Review,57,1701-1777
article,Knowledge and Fourth Amendment Privacy,,,,2016,,Northwestern University Law Review,111,139-210
article,Cell Phone Location Data and the Fourth Amendment,,,,2011,,Maryland Law Review,70,681-753
article,The Case Against the Case for Third-Party Doctrine,,,,2009,,Berkeley Technology Law Journal,24,1239-1253
article,Beyond the (Current) Fourth Amendment,,,,2007,,Pepperdine Law Review,34,975-1036
CSVEOF
chown ga:ga /home/ga/Documents/correct_citations.csv
echo "Reference CSV written to /home/ga/Documents/correct_citations.csv"

# Relaunch Jurism so the agent can interact with it via the GUI
echo "Relaunching Jurism..."
setsid sudo -u ga bash -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus DISPLAY=:1 /opt/jurism/jurism --no-remote >> /home/ga/jurism.log 2>&1 &'
sleep 8

# Wait for Jurism to load and dismiss any in-app alert dialogs
if type wait_and_dismiss_jurism_alerts &>/dev/null; then
    wait_and_dismiss_jurism_alerts 45
else
    sleep 10
fi

# Maximize and focus Jurism window
DISPLAY=:1 wmctrl -r "Jurism" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Jurism" 2>/dev/null || true
sleep 1

# Take start screenshot
DISPLAY=:1 import -window root /tmp/journal_submission_library_audit_start.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/journal_submission_library_audit_start.png 2>/dev/null || true
echo "Start screenshot saved to /tmp/journal_submission_library_audit_start.png"

echo "=== journal_submission_library_audit task setup complete ==="
echo "Library contains $ITEM_COUNT items ready for audit and organization."
