#!/bin/bash
set -e
echo "=== Setting up merge_duplicate_cases task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Jurism is running initially to locate DB, then close it
ensure_jurism_running
sleep 2

# Get database path
DB_PATH=$(get_jurism_db)
if [ -z "$DB_PATH" ]; then
    echo "ERROR: Jurism database not found"
    exit 1
fi
echo "Database found: $DB_PATH"

# Stop Jurism to perform database injection (avoids locks)
echo "Stopping Jurism for data injection..."
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 5

# Clear existing items to ensure clean state
sqlite3 "$DB_PATH" "DELETE FROM itemCreators; DELETE FROM itemData; DELETE FROM collectionItems; DELETE FROM items WHERE itemTypeID NOT IN (1,3,14,31); DELETE FROM deletedItems;" 2>/dev/null || true

# Inject 13 items: 10 originals + 3 duplicates with defects
# We use a python script to ensure precise control over field values
python3 - <<EOF
import sqlite3
import random
import string
import time
from datetime import datetime, timedelta

db_path = "$DB_PATH"
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

# Field IDs for Jurism 6
FIELDS = {
    "title": 1, "abstractNote": 2, "publicationTitle": 7, "date": 8,
    "volume": 22, "pages": 47, "reporter": 49, "caseName": 58,
    "court": 60, "reporterVolume": 66, "firstPage": 67, "dateDecided": 69
}

# Item Type IDs
TYPE_CASE = 9
TYPE_ARTICLE = 24

def get_value_id(val):
    cursor.execute("SELECT valueID FROM itemDataValues WHERE value = ?", (str(val),))
    row = cursor.fetchone()
    if row: return row[0]
    cursor.execute("INSERT INTO itemDataValues (value) VALUES (?)", (str(val),))
    return cursor.lastrowid

def add_item(type_id, fields, library_id=1):
    key = ''.join(random.choices(string.ascii_uppercase + string.digits, k=8))
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    cursor.execute(
        "INSERT INTO items (itemTypeID, dateAdded, dateModified, clientDateModified, libraryID, key) VALUES (?, ?, ?, ?, ?, ?)",
        (type_id, now, now, now, library_id, key)
    )
    item_id = cursor.lastrowid
    
    for field, value in fields.items():
        if value is None: continue
        fid = FIELDS.get(field)
        if not fid: continue
        vid = get_value_id(value)
        cursor.execute("INSERT INTO itemData (itemID, fieldID, valueID) VALUES (?, ?, ?)", (item_id, fid, vid))
    return item_id

# --- 1. Insert 7 Original Supreme Court Cases (Good Data) ---
cases = [
    {"caseName": "Brown v. Board of Education", "dateDecided": "1954", "court": "United States Supreme Court", "abstractNote": "Landmark Supreme Court case that declared racial segregation in public schools unconstitutional, overturning Plessy v. Ferguson."},
    {"caseName": "Marbury v. Madison", "dateDecided": "1803", "court": "United States Supreme Court", "abstractNote": "Foundational case establishing the principle of judicial review."},
    {"caseName": "Miranda v. Arizona", "dateDecided": "1966", "court": "United States Supreme Court", "abstractNote": "Case establishing the Miranda warning requirement for suspects in police custody."},
    {"caseName": "New York Times Co. v. Sullivan", "dateDecided": "1964", "court": "United States Supreme Court"},
    {"caseName": "Gideon v. Wainwright", "dateDecided": "1963", "court": "United States Supreme Court", "abstractNote": "Case holding that the Sixth Amendment right to counsel applies to state criminal proceedings."},
    {"caseName": "Obergefell v. Hodges", "dateDecided": "2015", "court": "United States Supreme Court"},
    {"caseName": "Tinker v. Des Moines Independent Community School District", "dateDecided": "1969", "court": "United States Supreme Court"}
]

for c in cases:
    add_item(TYPE_CASE, c)

# --- 2. Insert 3 Law Review Articles (Good Data) ---
articles = [
    {"title": "The Path of the Law", "publicationTitle": "Harvard Law Review", "date": "1897"},
    {"title": "Constitutional Fact Review", "publicationTitle": "Columbia Law Review", "date": "1985"},
    {"title": "The Due Process Clause", "publicationTitle": "Yale Law Journal", "date": "1971"}
]

for a in articles:
    add_item(TYPE_ARTICLE, a)

# --- 3. Insert 3 DUPLICATE Cases (Defective Data) ---
# Duplicate 1: Brown v. Board (Truncated Abstract)
add_item(TYPE_CASE, {
    "caseName": "Brown v. Board of Education", 
    "dateDecided": "1954", 
    "court": "United States Supreme Court", 
    "abstractNote": "Landmark Supreme Court case." # TRUNCATED
})

# Duplicate 2: Miranda (Missing Abstract)
add_item(TYPE_CASE, {
    "caseName": "Miranda v. Arizona", 
    "dateDecided": "1966", 
    "court": "United States Supreme Court",
    "abstractNote": None # MISSING
})

# Duplicate 3: Gideon (Missing Court)
add_item(TYPE_CASE, {
    "caseName": "Gideon v. Wainwright", 
    "dateDecided": "1963", 
    "court": None, # MISSING
    "abstractNote": "Case holding that the Sixth Amendment right to counsel applies to state criminal proceedings."
})

conn.commit()
conn.close()
EOF

echo "Data injection complete."

# Record initial counts
INITIAL_TOTAL=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1,3,14,31)" 2>/dev/null)
INITIAL_DELETED=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM deletedItems" 2>/dev/null)
echo "$INITIAL_TOTAL" > /tmp/initial_count.txt
echo "$INITIAL_DELETED" > /tmp/initial_deleted.txt
echo "Initial Library Items: $INITIAL_TOTAL (Expected 13)"
echo "Initial Deleted Items: $INITIAL_DELETED"

# Restart Jurism
echo "Relaunching Jurism..."
setsid sudo -u ga bash -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus DISPLAY=:1 /opt/jurism/jurism --no-remote > /home/ga/jurism.log 2>&1 &'
sleep 10

# Wait for and dismiss alerts
wait_and_dismiss_jurism_alerts 45

# Maximize and focus
DISPLAY=:1 wmctrl -r "Jurism" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Jurism" 2>/dev/null || true

# Capture initial screenshot
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="