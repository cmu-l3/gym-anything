#!/bin/bash
set -e
echo "=== Exporting import_dive_log result ==="

export DISPLAY="${DISPLAY:-:1}"

# Take a final screenshot as evidence of the UI state
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true

# Gather initial state variables
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_dive_count.txt 2>/dev/null || echo "0")
IMPORT_COUNT=$(cat /tmp/import_dive_count.txt 2>/dev/null || echo "0")
EXPECTED_TOTAL=$(cat /tmp/total_dive_count.txt 2>/dev/null || echo "0")
INITIAL_HASH=$(cat /tmp/initial_file_hash.txt 2>/dev/null || echo "")

MAIN_FILE="/home/ga/Documents/dives.ssrf"
IMPORT_FILE="/home/ga/Documents/import_dives.ssrf"

# Examine final main file
FILE_EXISTS="false"
FILE_MTIME="0"
CURRENT_HASH=""
FINAL_COUNT="0"
FINAL_TRIPS="0"

if [ -f "$MAIN_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$MAIN_FILE" 2>/dev/null || echo "0")
    CURRENT_HASH=$(md5sum "$MAIN_FILE" | cut -d' ' -f1)
    
    # Parse final XML with Python to extract the resulting dive and trip counts
    FINAL_COUNT=$(python3 -c "
import xml.etree.ElementTree as ET
try:
    tree = ET.parse('$MAIN_FILE')
    print(sum(1 for _ in tree.iter('dive')))
except:
    print('0')
")

    FINAL_TRIPS=$(python3 -c "
import xml.etree.ElementTree as ET
try:
    tree = ET.parse('$MAIN_FILE')
    print(sum(1 for _ in tree.iter('trip')))
except:
    print('0')
")
fi

IMPORT_EXISTS="false"
if [ -f "$IMPORT_FILE" ]; then
    IMPORT_EXISTS="true"
fi

# Bundle results in JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "initial_dive_count": $INITIAL_COUNT,
    "import_dive_count": $IMPORT_COUNT,
    "expected_total_count": $EXPECTED_TOTAL,
    "initial_file_hash": "$INITIAL_HASH",
    "main_file_exists": $FILE_EXISTS,
    "main_file_mtime": $FILE_MTIME,
    "final_file_hash": "$CURRENT_HASH",
    "final_dive_count": $FINAL_COUNT,
    "final_trip_count": $FINAL_TRIPS,
    "import_file_exists": $IMPORT_EXISTS,
    "screenshot_path": "/tmp/task_final_state.png"
}
EOF

# Move to the final location and clean up
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="