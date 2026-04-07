#!/bin/bash
# Do NOT use set -e
echo "=== Exporting temperature_science_report task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

su - ga -c "$SUGAR_ENV scrot /tmp/temperature_task_end.png" 2>/dev/null || true

ODT_FILE="/home/ga/Documents/temperature_report.odt"
TASK_START=$(cat /tmp/temperature_science_report_start_ts 2>/dev/null || echo "0")

FILE_EXISTS="false"
FILE_SIZE=0
FILE_MODIFIED="false"
HAS_TABLE="false"
HAS_ANALYSIS="false"
HAS_CONCLUSION="false"
HAS_TEMP_22="false"
HAS_TEMP_24="false"
HAS_TEMP_26="false"
HAS_ALL_TEMPS="false"

if [ -f "$ODT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat --format=%s "$ODT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat --format=%Y "$ODT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    echo "Found: $ODT_FILE ($FILE_SIZE bytes)"

    # Parse the ODT file (ZIP+XML) using Python
    python3 << 'PYEOF' > /tmp/temperature_analysis.json 2>/dev/null || echo '{"error":"parse_failed"}' > /tmp/temperature_analysis.json
import json
import zipfile
import xml.etree.ElementTree as ET
import re

result = {
    "has_table": False,
    "has_analysis": False,
    "has_conclusion": False,
    "has_temp_22": False,
    "has_temp_24": False,
    "has_temp_21": False,
    "has_temp_26": False,
    "has_temp_23": False,
    "temps_found": [],
    "error": None
}

odt_file = "/home/ga/Documents/temperature_report.odt"

try:
    with zipfile.ZipFile(odt_file, 'r') as z:
        with z.open('content.xml') as f:
            content = f.read().decode('utf-8')

    # Get plain text
    plain_text = re.sub(r'<[^>]+>', ' ', content).lower()
    plain_text = plain_text.replace('&amp;', '&').replace('&lt;', '<').replace('&gt;', '>')

    result["has_analysis"] = bool(re.search(r'\banalysis\b', plain_text))
    result["has_conclusion"] = bool(re.search(r'\bconclusion\b', plain_text))
    result["has_table"] = 'table:table' in content or '<table' in content.lower()

    # Check for specific temperature values
    # These might appear as "22", "22°C", "22 C", etc.
    result["has_temp_22"] = bool(re.search(r'\b22\b', plain_text))
    result["has_temp_24"] = bool(re.search(r'\b24\b', plain_text))
    result["has_temp_21"] = bool(re.search(r'\b21\b', plain_text))
    result["has_temp_26"] = bool(re.search(r'\b26\b', plain_text))
    result["has_temp_23"] = bool(re.search(r'\b23\b', plain_text))

    temps_found = []
    for temp, key in [(22, "has_temp_22"), (24, "has_temp_24"), (21, "has_temp_21"),
                      (26, "has_temp_26"), (23, "has_temp_23")]:
        if result[key]:
            temps_found.append(temp)
    result["temps_found"] = temps_found

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

    if [ -f /tmp/temperature_analysis.json ]; then
        HAS_TABLE=$(python3 -c "import json; d=json.load(open('/tmp/temperature_analysis.json')); print(str(d.get('has_table',False)).lower())" 2>/dev/null || echo "false")
        HAS_ANALYSIS=$(python3 -c "import json; d=json.load(open('/tmp/temperature_analysis.json')); print(str(d.get('has_analysis',False)).lower())" 2>/dev/null || echo "false")
        HAS_CONCLUSION=$(python3 -c "import json; d=json.load(open('/tmp/temperature_analysis.json')); print(str(d.get('has_conclusion',False)).lower())" 2>/dev/null || echo "false")
        HAS_TEMP_22=$(python3 -c "import json; d=json.load(open('/tmp/temperature_analysis.json')); print(str(d.get('has_temp_22',False)).lower())" 2>/dev/null || echo "false")
        HAS_TEMP_24=$(python3 -c "import json; d=json.load(open('/tmp/temperature_analysis.json')); print(str(d.get('has_temp_24',False)).lower())" 2>/dev/null || echo "false")
        HAS_TEMP_26=$(python3 -c "import json; d=json.load(open('/tmp/temperature_analysis.json')); print(str(d.get('has_temp_26',False)).lower())" 2>/dev/null || echo "false")

        TEMPS_COUNT=$(python3 -c "import json; d=json.load(open('/tmp/temperature_analysis.json')); print(len(d.get('temps_found',[])))" 2>/dev/null || echo "0")
        if [ "$TEMPS_COUNT" -ge 5 ]; then
            HAS_ALL_TEMPS="true"
        fi
    fi
fi

cat > /tmp/temperature_science_report_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_modified": $FILE_MODIFIED,
    "has_table": $HAS_TABLE,
    "has_analysis": $HAS_ANALYSIS,
    "has_conclusion": $HAS_CONCLUSION,
    "has_temp_22": $HAS_TEMP_22,
    "has_temp_24": $HAS_TEMP_24,
    "has_temp_26": $HAS_TEMP_26,
    "has_all_temps": $HAS_ALL_TEMPS
}
EOF

chmod 666 /tmp/temperature_science_report_result.json
echo "Result saved to /tmp/temperature_science_report_result.json"
cat /tmp/temperature_science_report_result.json
echo "=== Export complete ==="
