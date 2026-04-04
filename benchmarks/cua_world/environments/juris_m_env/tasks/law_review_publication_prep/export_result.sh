#!/bin/bash
echo "=== Exporting law_review_publication_prep Result ==="

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
    cat > /tmp/law_review_publication_prep_result.json << 'EOF'
{"error": "Jurism database not found", "passed": false}
EOF
    exit 1
fi

echo "Using database: $JURISM_DB"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/law_review_final.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/law_review_final.png 2>/dev/null || true
echo "Screenshot saved"

# Kill Jurism to flush prefs.js to disk and release SQLite lock
pkill -f "/opt/jurism/jurism" 2>/dev/null || true
sleep 3
echo "Jurism stopped for database export"

python3 << PYEOF
import sqlite3, json, sys, os, glob, re
from datetime import datetime

JURISM_DB = "$JURISM_DB"

try:
    conn = sqlite3.connect(JURISM_DB)
    c = conn.cursor()
except Exception as e:
    result = {"error": str(e), "export_timestamp": datetime.now().isoformat()}
    with open("/tmp/law_review_publication_prep_result.json", "w") as f:
        json.dump(result, f, indent=2)
    sys.exit(0)

# ---------------------------------------------------------------------------
# 1. Collection hierarchy
# ---------------------------------------------------------------------------
def get_collection_id(conn, name, parent_id=None):
    c = conn.cursor()
    if parent_id is None:
        c.execute("SELECT collectionID FROM collections WHERE collectionName=? AND (parentCollectionID IS NULL OR parentCollectionID=0) AND libraryID=1", (name,))
    else:
        c.execute("SELECT collectionID FROM collections WHERE collectionName=? AND parentCollectionID=? AND libraryID=1", (name, parent_id))
    r = c.fetchone()
    return r[0] if r else None

parent_id = get_collection_id(conn, "Tech & Privacy Special Issue")
parent_collection_exists = parent_id is not None

data_privacy_id = get_collection_id(conn, "Data Privacy Articles", parent_id) if parent_id else None
digital_search_id = get_collection_id(conn, "Digital Search Cases", parent_id) if parent_id else None
surveillance_law_id = get_collection_id(conn, "Surveillance Law", parent_id) if parent_id else None

data_privacy_subcollection_exists = data_privacy_id is not None
digital_search_subcollection_exists = digital_search_id is not None
surveillance_law_subcollection_exists = surveillance_law_id is not None

# ---------------------------------------------------------------------------
# 2. Items per subcollection
# ---------------------------------------------------------------------------
def get_subcollection_items(conn, coll_id):
    if not coll_id:
        return []
    c = conn.cursor()
    c.execute("""
        SELECT COALESCE(
            (SELECT idv.value FROM itemData id2 JOIN itemDataValues idv ON id2.valueID=idv.valueID WHERE id2.itemID=ci.itemID AND id2.fieldID=1),
            (SELECT idv.value FROM itemData id2 JOIN itemDataValues idv ON id2.valueID=idv.valueID WHERE id2.itemID=ci.itemID AND id2.fieldID=58),
            'Unknown'
        ) FROM collectionItems ci WHERE ci.collectionID=?
    """, (coll_id,))
    return [r[0] for r in c.fetchall()]

data_privacy_items = get_subcollection_items(conn, data_privacy_id)
digital_search_items = get_subcollection_items(conn, digital_search_id)
surveillance_law_items = get_subcollection_items(conn, surveillance_law_id)

# Total unique items assigned to any subcollection
c.execute("""
    SELECT COUNT(DISTINCT ci.itemID)
    FROM collectionItems ci
    JOIN collections col ON ci.collectionID=col.collectionID
    WHERE col.libraryID=1
""")
r = c.fetchone()
total_assigned_items = r[0] if r else 0

# ---------------------------------------------------------------------------
# 3. Items with / without abstract
# ---------------------------------------------------------------------------
c.execute("""
SELECT
  COALESCE(
    (SELECT idv.value FROM itemData id2 JOIN itemDataValues idv ON id2.valueID=idv.valueID WHERE id2.itemID=i.itemID AND id2.fieldID=1),
    (SELECT idv.value FROM itemData id2 JOIN itemDataValues idv ON id2.valueID=idv.valueID WHERE id2.itemID=i.itemID AND id2.fieldID=58),
    'Unknown'
  ) as displayName,
  COALESCE((SELECT idv.value FROM itemData id2 JOIN itemDataValues idv ON id2.valueID=idv.valueID WHERE id2.itemID=i.itemID AND id2.fieldID=2),'') as abstractNote
FROM items i WHERE i.libraryID=1 AND i.itemTypeID NOT IN (1,3,31)
""")
rows = c.fetchall()

items_with_abstract = [row[0] for row in rows if row[1] and row[1].strip()]
items_without_abstract = [row[0] for row in rows if not row[1] or not row[1].strip()]
total_items = len(rows)

# ---------------------------------------------------------------------------
# 4. Standalone notes (Table of Contents)
# ---------------------------------------------------------------------------
try:
    c.execute("""
        SELECT n.title, LENGTH(n.note) as note_length
        FROM itemNotes n
        JOIN items i ON n.itemID=i.itemID
        WHERE (n.parentItemID IS NULL OR n.parentItemID NOT IN (SELECT itemID FROM items WHERE libraryID=1 AND itemTypeID NOT IN (1,3,31)))
        AND i.libraryID=1
    """)
    standalone_notes = [{"title": row[0] or "", "note_length": row[1] or 0} for row in c.fetchall()]
except Exception:
    # Fallback query if itemNotes schema differs
    try:
        c.execute("""
            SELECT i.itemID,
                   COALESCE((SELECT idv.value FROM itemData id2 JOIN itemDataValues idv ON id2.valueID=idv.valueID WHERE id2.itemID=i.itemID AND id2.fieldID=1), '') as title,
                   '' as note_text
            FROM items i
            WHERE i.itemTypeID=1 AND i.libraryID=1
        """)
        standalone_notes = [{"title": row[1], "note_length": 0} for row in c.fetchall()]
    except Exception:
        standalone_notes = []

# ---------------------------------------------------------------------------
# 5. Tags — count items tagged 'tech-privacy-2024'
# ---------------------------------------------------------------------------
try:
    c.execute("""
        SELECT COUNT(DISTINCT it.itemID)
        FROM itemTags it
        JOIN tags t ON it.tagID=t.tagID
        WHERE t.name='tech-privacy-2024' AND it.itemID IN (SELECT itemID FROM items WHERE libraryID=1)
    """)
    r = c.fetchone()
    total_items_with_tag = r[0] if r else 0
except Exception:
    total_items_with_tag = 0

# ---------------------------------------------------------------------------
# 6. Quick Copy citation style from prefs.js
# ---------------------------------------------------------------------------
quick_copy_style = ""
prefs_files = (
    glob.glob('/home/ga/.zotero/zotero/*/prefs.js') +
    glob.glob('/home/ga/.jurism/jurism/*/prefs.js')
)
for pf in prefs_files:
    try:
        content = open(pf).read()
        m = re.search(r'quickCopy\.setting["\s,=]+["\']([^"\']+)["\']', content)
        if m:
            quick_copy_style = m.group(1)
            break
    except Exception:
        pass

conn.close()

result = {
    "parent_collection_exists": parent_collection_exists,
    "data_privacy_subcollection_exists": data_privacy_subcollection_exists,
    "digital_search_subcollection_exists": digital_search_subcollection_exists,
    "surveillance_law_subcollection_exists": surveillance_law_subcollection_exists,
    "data_privacy_items": data_privacy_items,
    "digital_search_items": digital_search_items,
    "surveillance_law_items": surveillance_law_items,
    "total_assigned_items": total_assigned_items,
    "items_with_abstract": items_with_abstract,
    "items_without_abstract": items_without_abstract,
    "standalone_notes": standalone_notes,
    "total_items_with_tag": total_items_with_tag,
    "quick_copy_style": quick_copy_style,
    "total_items": total_items,
    "export_timestamp": datetime.now().isoformat(),
}

with open("/tmp/law_review_publication_prep_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
print("Result written to /tmp/law_review_publication_prep_result.json")
PYEOF

chmod 666 /tmp/law_review_publication_prep_result.json 2>/dev/null || true
echo "=== Export Complete ==="
cat /tmp/law_review_publication_prep_result.json
