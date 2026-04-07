#!/bin/bash
echo "=== Exporting pendulum_gravity_lab_report task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Capture final screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/pendulum_task_end.png" 2>/dev/null || true

ODT_FILE="/home/ga/Documents/pendulum_report.odt"
TASK_START=$(cat /tmp/pendulum_gravity_start_ts 2>/dev/null || echo "0")

FILE_EXISTS="false"
FILE_SIZE=0
FILE_MODIFIED="false"

if [ -f "$ODT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat --format=%s "$ODT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat --format=%Y "$ODT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    echo "Found: $ODT_FILE ($FILE_SIZE bytes)"

    # Parse the ODT file (ZIP archive + XML content) using Python
    python3 << 'PYEOF' > /tmp/pendulum_analysis.json 2>/dev/null || echo '{"error":"parse_failed"}' > /tmp/pendulum_analysis.json
import json
import zipfile
import xml.etree.ElementTree as ET
import re

result = {
    "has_intro": False,
    "has_data_results": False,
    "has_conclusion": False,
    "has_table": False,
    "has_9_79": False,
    "has_9_84": False,
    "has_9_85": False,
    "has_9_81": False,
    "error": None
}

odt_file = "/home/ga/Documents/pendulum_report.odt"

try:
    with zipfile.ZipFile(odt_file, 'r') as z:
        with z.open('content.xml') as f:
            content = f.read().decode('utf-8')

    # Convert XML text into lowercased plain text for easier string matching
    plain_text = re.sub(r'<[^>]+>', ' ', content).lower()
    plain_text = plain_text.replace('&amp;', '&').replace('&lt;', '<').replace('&gt;', '>')

    # Check for exact headings requirement
    result["has_intro"] = bool(re.search(r'\bintroduction\b', plain_text))
    result["has_data_results"] = bool(re.search(r'\bdata and results\b', plain_text))
    result["has_conclusion"] = bool(re.search(r'\bconclusion\b', plain_text))
    
    # Check for proper ODT table markup
    result["has_table"] = 'table:table' in content or '<table' in content.lower()

    # Check for required mathematical computation outputs
    # Looking for exact string matches on the calculated rounding values
    result["has_9_79"] = bool(re.search(r'\b9\.79\b', plain_text))
    result["has_9_84"] = bool(re.search(r'\b9\.84\b', plain_text))
    result["has_9_85"] = bool(re.search(r'\b9\.85\b', plain_text))
    result["has_9_81"] = bool(re.search(r'\b9\.81\b', plain_text))

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

else:
    echo '{"error":"file_not_found"}' > /tmp/pendulum_analysis.json
fi

# Load variables from python parse analysis
HAS_INTRO=$(python3 -c "import json; d=json.load(open('/tmp/pendulum_analysis.json')); print(str(d.get('has_intro',False)).lower())" 2>/dev/null || echo "false")
HAS_DATA_RESULTS=$(python3 -c "import json; d=json.load(open('/tmp/pendulum_analysis.json')); print(str(d.get('has_data_results',False)).lower())" 2>/dev/null || echo "false")
HAS_CONCLUSION=$(python3 -c "import json; d=json.load(open('/tmp/pendulum_analysis.json')); print(str(d.get('has_conclusion',False)).lower())" 2>/dev/null || echo "false")
HAS_TABLE=$(python3 -c "import json; d=json.load(open('/tmp/pendulum_analysis.json')); print(str(d.get('has_table',False)).lower())" 2>/dev/null || echo "false")
HAS_9_79=$(python3 -c "import json; d=json.load(open('/tmp/pendulum_analysis.json')); print(str(d.get('has_9_79',False)).lower())" 2>/dev/null || echo "false")
HAS_9_84=$(python3 -c "import json; d=json.load(open('/tmp/pendulum_analysis.json')); print(str(d.get('has_9_84',False)).lower())" 2>/dev/null || echo "false")
HAS_9_85=$(python3 -c "import json; d=json.load(open('/tmp/pendulum_analysis.json')); print(str(d.get('has_9_85',False)).lower())" 2>/dev/null || echo "false")
HAS_9_81=$(python3 -c "import json; d=json.load(open('/tmp/pendulum_analysis.json')); print(str(d.get('has_9_81',False)).lower())" 2>/dev/null || echo "false")

cat > /tmp/pendulum_gravity_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_modified": $FILE_MODIFIED,
    "has_intro": $HAS_INTRO,
    "has_data_results": $HAS_DATA_RESULTS,
    "has_conclusion": $HAS_CONCLUSION,
    "has_table": $HAS_TABLE,
    "has_9_79": $HAS_9_79,
    "has_9_84": $HAS_9_84,
    "has_9_85": $HAS_9_85,
    "has_9_81": $HAS_9_81
}
EOF

chmod 666 /tmp/pendulum_gravity_result.json
echo "Result saved to /tmp/pendulum_gravity_result.json"
cat /tmp/pendulum_gravity_result.json
echo "=== Export complete ==="