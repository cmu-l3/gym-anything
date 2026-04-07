#!/bin/bash
echo "=== Exporting correct_station_metadata task results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# 1. Get final elevations from the database
echo "Fetching final database state..."
mysql -u sysop -psysop seiscomp -N -e "SELECT code, elevation FROM Station WHERE code IN ('TOLI', 'GSI', 'KWP', 'SANI', 'BKB');" > /tmp/final_elevations.txt 2>/dev/null || true

# 2. Check for the output XML file
OUTPUT_XML="/home/ga/seiscomp/var/lib/inventory/corrected_inventory.xml"
XML_EXISTS="false"
XML_CREATED_DURING_TASK="false"
XML_SIZE=0

if [ -f "$OUTPUT_XML" ]; then
    XML_EXISTS="true"
    XML_SIZE=$(stat -c %s "$OUTPUT_XML" 2>/dev/null || echo "0")
    XML_MTIME=$(stat -c %Y "$OUTPUT_XML" 2>/dev/null || echo "0")
    
    if [ "$XML_MTIME" -gt "$TASK_START" ]; then
        XML_CREATED_DURING_TASK="true"
    fi
fi

# 3. Check for the text report
OUTPUT_TXT="/home/ga/station_correction_report.txt"
TXT_EXISTS="false"
TXT_CREATED_DURING_TASK="false"
TXT_SIZE=0

if [ -f "$OUTPUT_TXT" ]; then
    TXT_EXISTS="true"
    TXT_SIZE=$(stat -c %s "$OUTPUT_TXT" 2>/dev/null || echo "0")
    TXT_MTIME=$(stat -c %Y "$OUTPUT_TXT" 2>/dev/null || echo "0")
    
    if [ "$TXT_MTIME" -gt "$TASK_START" ]; then
        TXT_CREATED_DURING_TASK="true"
    fi
fi

# 4. Read the initial and final DB values into JSON format using Python
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

python3 - <<EOF > "$TEMP_JSON"
import json
import os

def read_elevations(filepath):
    data = {}
    if os.path.exists(filepath):
        with open(filepath, 'r') as f:
            for line in f:
                parts = line.strip().split('\t')
                if len(parts) >= 2:
                    try:
                        data[parts[0]] = float(parts[1])
                    except ValueError:
                        pass
    return data

initial_elevations = read_elevations('/tmp/initial_elevations.txt')
final_elevations = read_elevations('/tmp/final_elevations.txt')

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_db_elevations": initial_elevations,
    "final_db_elevations": final_elevations,
    "xml_file": {
        "exists": "$XML_EXISTS" == "true",
        "created_during_task": "$XML_CREATED_DURING_TASK" == "true",
        "size_bytes": $XML_SIZE,
        "path": "$OUTPUT_XML"
    },
    "txt_file": {
        "exists": "$TXT_EXISTS" == "true",
        "created_during_task": "$TXT_CREATED_DURING_TASK" == "true",
        "size_bytes": $TXT_SIZE,
        "path": "$OUTPUT_TXT"
    }
}

with open('$TEMP_JSON', 'w') as f:
    json.dump(result, f, indent=4)
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved:"
cat /tmp/task_result.json
echo "=== Export complete ==="