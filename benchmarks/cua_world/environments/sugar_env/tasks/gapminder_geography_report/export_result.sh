#!/bin/bash
# Export script for gapminder_geography_report task
echo "=== Exporting gapminder_geography_report task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Take final screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/gapminder_task_end.png" 2>/dev/null || true

ODT_FILE="/home/ga/Documents/development_report.odt"
TASK_START=$(cat /tmp/gapminder_report_start_ts 2>/dev/null || echo "0")

FILE_EXISTS="false"
FILE_SIZE=0
FILE_MODIFIED="false"
HAS_TABLE="false"
HAS_SUBJECTS="false"
HAS_RWANDA_POP="false"
HAS_SWEDEN_POP="false"
HAS_RWANDA_CALC="false"
HAS_SWEDEN_CALC="false"

if [ -f "$ODT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat --format=%s "$ODT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat --format=%Y "$ODT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    echo "Found: $ODT_FILE ($FILE_SIZE bytes)"

    # Parse the ODT file (ZIP+XML) using Python
    python3 << 'PYEOF' > /tmp/gapminder_analysis.json 2>/dev/null || echo '{"error":"parse_failed"}' > /tmp/gapminder_analysis.json
import json
import zipfile
import xml.etree.ElementTree as ET
import re

result = {
    "has_table": False,
    "has_subjects": False,
    "has_rwanda_pop": False,
    "has_sweden_pop": False,
    "has_rwanda_calc": False,
    "has_sweden_calc": False,
    "error": None
}

odt_file = "/home/ga/Documents/development_report.odt"

try:
    with zipfile.ZipFile(odt_file, 'r') as z:
        with z.open('content.xml') as f:
            content = f.read().decode('utf-8')

    # Get plain text by stripping XML tags
    plain_text = re.sub(r'<[^>]+>', ' ', content).lower()
    plain_text = plain_text.replace('&amp;', '&').replace('&lt;', '<').replace('&gt;', '>')

    # Check for structural table
    result["has_table"] = 'table:table' in content or '<table' in content.lower()

    # Check for mentions of subjects
    result["has_subjects"] = bool(re.search(r'rwanda', plain_text)) and bool(re.search(r'sweden', plain_text))

    # Check for specific unrounded population figures (allowing optional commas/dots)
    # Rwanda 1952 Pop: 2534927
    result["has_rwanda_pop"] = bool(re.search(r'2[,.\s]?534[,.\s]?927', plain_text))
    # Sweden 2007 Pop: 9031088
    result["has_sweden_pop"] = bool(re.search(r'9[,.\s]?031[,.\s]?088', plain_text))

    # Check for specific calculations (Life Expectancy differences)
    # Rwanda Change: 46.242 - 40.0 = 6.242
    result["has_rwanda_calc"] = bool(re.search(r'6\.242|6\.24|6\.2\b', plain_text))
    # Sweden Change: 80.884 - 71.86 = 9.024
    result["has_sweden_calc"] = bool(re.search(r'9\.024|9\.02|9\.0\b', plain_text))

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

    if [ -f /tmp/gapminder_analysis.json ]; then
        HAS_TABLE=$(python3 -c "import json; d=json.load(open('/tmp/gapminder_analysis.json')); print(str(d.get('has_table',False)).lower())" 2>/dev/null || echo "false")
        HAS_SUBJECTS=$(python3 -c "import json; d=json.load(open('/tmp/gapminder_analysis.json')); print(str(d.get('has_subjects',False)).lower())" 2>/dev/null || echo "false")
        HAS_RWANDA_POP=$(python3 -c "import json; d=json.load(open('/tmp/gapminder_analysis.json')); print(str(d.get('has_rwanda_pop',False)).lower())" 2>/dev/null || echo "false")
        HAS_SWEDEN_POP=$(python3 -c "import json; d=json.load(open('/tmp/gapminder_analysis.json')); print(str(d.get('has_sweden_pop',False)).lower())" 2>/dev/null || echo "false")
        HAS_RWANDA_CALC=$(python3 -c "import json; d=json.load(open('/tmp/gapminder_analysis.json')); print(str(d.get('has_rwanda_calc',False)).lower())" 2>/dev/null || echo "false")
        HAS_SWEDEN_CALC=$(python3 -c "import json; d=json.load(open('/tmp/gapminder_analysis.json')); print(str(d.get('has_sweden_calc',False)).lower())" 2>/dev/null || echo "false")
    fi
fi

# Generate final JSON result
cat > /tmp/gapminder_geography_report_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_modified": $FILE_MODIFIED,
    "has_table": $HAS_TABLE,
    "has_subjects": $HAS_SUBJECTS,
    "has_rwanda_pop": $HAS_RWANDA_POP,
    "has_sweden_pop": $HAS_SWEDEN_POP,
    "has_rwanda_calc": $HAS_RWANDA_CALC,
    "has_sweden_calc": $HAS_SWEDEN_CALC
}
EOF

chmod 666 /tmp/gapminder_geography_report_result.json
echo "Result saved to /tmp/gapminder_geography_report_result.json"
cat /tmp/gapminder_geography_report_result.json
echo "=== Export complete ==="