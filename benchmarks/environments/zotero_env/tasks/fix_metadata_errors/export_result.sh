#!/bin/bash
# export_result.sh for fix_metadata_errors
echo "=== Exporting results ==="

ZOTERO_DB="/home/ga/Zotero/zotero.sqlite"
RESULT_JSON="/tmp/task_result.json"

# Helper query function
query_val() {
    local sql="$1"
    sqlite3 "$ZOTERO_DB" "$sql" 2>/dev/null || echo ""
}

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Get Task Start and DB Modification Times
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DB_MTIME=$(stat -c %Y "$ZOTERO_DB" 2>/dev/null || echo "0")
echo "Task Start: $TASK_START"
echo "DB MTime:   $DB_MTIME"

# 3. Query Final Values
echo "Querying Einstein Date..."
# Field 6 = Date. Find item by title "On the Electrodynamics..."
EINSTEIN_DATE=$(query_val "
    SELECT v.value FROM itemData d
    JOIN itemDataValues v ON d.valueID = v.valueID
    WHERE d.fieldID = 6
      AND d.itemID = (
        SELECT d2.itemID FROM itemData d2
        JOIN itemDataValues v2 ON d2.valueID = v2.valueID
        WHERE d2.fieldID = 1 AND v2.value LIKE '%Electrodynamics%Moving Bodies%'
      );
")

echo "Querying LeCun DOI..."
# Field 59 = DOI. Find item "Deep Learning"
LECUN_DOI=$(query_val "
    SELECT v.value FROM itemData d
    JOIN itemDataValues v ON d.valueID = v.valueID
    WHERE d.fieldID = 59
      AND d.itemID = (
        SELECT d2.itemID FROM itemData d2
        JOIN itemDataValues v2 ON d2.valueID = v2.valueID
        WHERE d2.fieldID = 1 AND v2.value = 'Deep Learning'
      );
")
if [ -z "$LECUN_DOI" ]; then LECUN_DOI="MISSING"; fi

echo "Querying Turing Publication..."
# Field 38 = Publication. Find item "Computing Machinery..."
TURING_PUB=$(query_val "
    SELECT v.value FROM itemData d
    JOIN itemDataValues v ON d.valueID = v.valueID
    WHERE d.fieldID = 38
      AND d.itemID = (
        SELECT d2.itemID FROM itemData d2
        JOIN itemDataValues v2 ON d2.valueID = v2.valueID
        WHERE d2.fieldID = 1 AND v2.value LIKE '%Computing Machinery%Intelligence%'
      );
")

# 4. Write JSON
# Use Python to write JSON safely to handle potential quotes/newlines
python3 <<EOF
import json
import os

data = {
    "task_start": $TASK_START,
    "db_mtime": $DB_MTIME,
    "einstein_date": """$EINSTEIN_DATE""",
    "lecun_doi": """$LECUN_DOI""",
    "turing_pub": """$TURING_PUB"""
}

# Clean strings (remove trailing newlines from shell capture)
for k, v in data.items():
    if isinstance(v, str):
        data[k] = v.strip()

print(json.dumps(data, indent=2))

with open("$RESULT_JSON", "w") as f:
    json.dump(data, f)
EOF

# Ensure permissions
chmod 666 "$RESULT_JSON"

echo "=== Export complete ==="
cat "$RESULT_JSON"