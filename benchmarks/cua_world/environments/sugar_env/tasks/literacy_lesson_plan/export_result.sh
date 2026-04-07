#!/bin/bash
# Do NOT use set -e
echo "=== Exporting literacy_lesson_plan task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

su - ga -c "$SUGAR_ENV scrot /tmp/literacy_task_end.png" 2>/dev/null || true

ODT_FILE="/home/ga/Documents/literacy_plan.odt"
TASK_START=$(cat /tmp/literacy_lesson_plan_start_ts 2>/dev/null || echo "0")

FILE_EXISTS="false"
FILE_SIZE=0
FILE_MODIFIED="false"
HAS_LEARNING_OBJ="false"
HAS_DAILY_SCHED="false"
HAS_ASSESSMENT="false"
HAS_TABLE="false"
HAS_MONDAY="false"
JOURNAL_TITLE_FOUND="false"

if [ -f "$ODT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat --format=%s "$ODT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat --format=%Y "$ODT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    echo "Found: $ODT_FILE ($FILE_SIZE bytes)"

    # Parse the ODT file (ZIP+XML) using Python
    python3 << 'PYEOF' > /tmp/literacy_analysis.json 2>/dev/null || echo '{"error":"parse_failed"}' > /tmp/literacy_analysis.json
import json
import zipfile
import xml.etree.ElementTree as ET
import re
import os

result = {
    "has_learning_obj": False,
    "has_daily_sched": False,
    "has_assessment": False,
    "has_table": False,
    "has_monday": False,
    "text_content": "",
    "error": None
}

odt_file = "/home/ga/Documents/literacy_plan.odt"

try:
    with zipfile.ZipFile(odt_file, 'r') as z:
        with z.open('content.xml') as f:
            content = f.read().decode('utf-8')

    # Strip XML tags to get plain text (for keyword search)
    plain_text = re.sub(r'<[^>]+>', ' ', content).lower()
    # Unescape common XML entities
    plain_text = plain_text.replace('&amp;', '&').replace('&lt;', '<').replace('&gt;', '>')

    result["text_content"] = plain_text[:2000]  # Truncate for JSON

    # Check for required headings/sections
    result["has_learning_obj"] = bool(re.search(r'learning\s+objectives?', plain_text))
    result["has_daily_sched"] = bool(re.search(r'daily\s+schedule', plain_text))
    result["has_assessment"] = bool(re.search(r'assessment', plain_text))
    result["has_monday"] = bool(re.search(r'monday', plain_text))

    # Check for table element in XML
    result["has_table"] = 'table:table' in content or '<table' in content.lower()

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

    if [ -f /tmp/literacy_analysis.json ]; then
        HAS_LEARNING_OBJ=$(python3 -c "import json; d=json.load(open('/tmp/literacy_analysis.json')); print(str(d.get('has_learning_obj',False)).lower())" 2>/dev/null || echo "false")
        HAS_DAILY_SCHED=$(python3 -c "import json; d=json.load(open('/tmp/literacy_analysis.json')); print(str(d.get('has_daily_sched',False)).lower())" 2>/dev/null || echo "false")
        HAS_ASSESSMENT=$(python3 -c "import json; d=json.load(open('/tmp/literacy_analysis.json')); print(str(d.get('has_assessment',False)).lower())" 2>/dev/null || echo "false")
        HAS_TABLE=$(python3 -c "import json; d=json.load(open('/tmp/literacy_analysis.json')); print(str(d.get('has_table',False)).lower())" 2>/dev/null || echo "false")
        HAS_MONDAY=$(python3 -c "import json; d=json.load(open('/tmp/literacy_analysis.json')); print(str(d.get('has_monday',False)).lower())" 2>/dev/null || echo "false")
    fi
fi

# Check Sugar Journal for "Literacy Plan Week 3"
JOURNAL_DIR="/home/ga/.sugar/default/datastore"
if [ -d "$JOURNAL_DIR" ]; then
    MATCH=$(find "$JOURNAL_DIR" -name "title" -exec grep -l "Literacy Plan Week 3" {} \; 2>/dev/null | head -1)
    if [ -n "$MATCH" ]; then
        JOURNAL_TITLE_FOUND="true"
        echo "Found Journal entry: Literacy Plan Week 3"
    fi
fi

cat > /tmp/literacy_lesson_plan_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_modified": $FILE_MODIFIED,
    "has_learning_obj": $HAS_LEARNING_OBJ,
    "has_daily_sched": $HAS_DAILY_SCHED,
    "has_assessment": $HAS_ASSESSMENT,
    "has_table": $HAS_TABLE,
    "has_monday": $HAS_MONDAY,
    "journal_title_found": $JOURNAL_TITLE_FOUND
}
EOF

chmod 666 /tmp/literacy_lesson_plan_result.json
echo "Result saved to /tmp/literacy_lesson_plan_result.json"
cat /tmp/literacy_lesson_plan_result.json
echo "=== Export complete ==="
