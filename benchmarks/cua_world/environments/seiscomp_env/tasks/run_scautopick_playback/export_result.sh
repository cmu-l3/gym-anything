#!/bin/bash
echo "=== Exporting run_scautopick_playback results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 1. Parse scautopick.cfg
CFG_FILE="/home/ga/seiscomp/etc/scautopick.cfg"
CFG_EXISTS="false"
CFG_TRIGGER_ON=""
CFG_TRIGGER_OFF=""
CFG_FILTER=""
CFG_TIME_CORR=""

if [ -f "$CFG_FILE" ]; then
    CFG_EXISTS="true"
    # Extract values, removing spaces and quotes to ensure strict equality
    CFG_TRIGGER_ON=$(grep -E "^[[:space:]]*thresholds\.triggerOn" "$CFG_FILE" | cut -d'=' -f2 | tr -d ' "' | head -1)
    CFG_TRIGGER_OFF=$(grep -E "^[[:space:]]*thresholds\.triggerOff" "$CFG_FILE" | cut -d'=' -f2 | tr -d ' "' | head -1)
    CFG_FILTER=$(grep -E "^[[:space:]]*filter" "$CFG_FILE" | cut -d'=' -f2 | tr -d ' "' | head -1)
    CFG_TIME_CORR=$(grep -E "^[[:space:]]*timeCorrection" "$CFG_FILE" | cut -d'=' -f2 | tr -d ' "' | head -1)
fi

# 2. Check bindings in SeisComP keyfiles
BINDING_COUNT=0
for STA in TOLI GSI KWP SANI BKB; do
    if grep -q "scautopick" "/home/ga/seiscomp/etc/key/station_GE_$STA" 2>/dev/null; then
        BINDING_COUNT=$((BINDING_COUNT + 1))
    fi
done

# 3. Check XML Output for programmatic validity
XML_FILE="/home/ga/Documents/autopicks.xml"
XML_MTIME=0
XML_SIZE=0
XML_VALID="false"
XML_PICK_COUNT=0

if [ -f "$XML_FILE" ]; then
    XML_MTIME=$(stat -c %Y "$XML_FILE" 2>/dev/null || echo "0")
    XML_SIZE=$(stat -c %s "$XML_FILE" 2>/dev/null || echo "0")
    
    # Use python to parse safely across XML standards and check for picks
    XML_INFO=$(python3 -c "
import sys, json
import xml.etree.ElementTree as ET
try:
    tree = ET.parse('$XML_FILE')
    # SeisComP ML and QuakeML have slightly different capitalizations, account for both
    count = sum(1 for el in tree.iter() if el.tag.endswith('Pick') or el.tag.endswith('pick'))
    print(json.dumps({'valid': True, 'count': count}))
except Exception as e:
    print(json.dumps({'valid': False, 'count': 0, 'error': str(e)}))
" 2>/dev/null || echo '{"valid": false, "count": 0}')
    
    XML_VALID=$(echo "$XML_INFO" | grep -q '"valid": true' && echo "true" || echo "false")
    XML_PICK_COUNT=$(echo "$XML_INFO" | grep -o '"count": [0-9]*' | cut -d' ' -f2 || echo "0")
fi

# 4. Check Text Summary Report
SUMMARY_FILE="/home/ga/Documents/pick_summary.txt"
SUMMARY_MTIME=0
SUMMARY_SIZE=0
SUMMARY_TOTAL=-1
STATIONS_FOUND=0
HEADER_FOUND="false"

if [ -f "$SUMMARY_FILE" ]; then
    SUMMARY_MTIME=$(stat -c %Y "$SUMMARY_FILE" 2>/dev/null || echo "0")
    SUMMARY_SIZE=$(stat -c %s "$SUMMARY_FILE" 2>/dev/null || echo "0")
    
    # Check for strict expected header
    if grep -q "=== Automatic Pick Summary ===" "$SUMMARY_FILE"; then
        HEADER_FOUND="true"
    fi
    
    # Extract total number reported
    SUMMARY_TOTAL=$(grep -i "Total picks:" "$SUMMARY_FILE" | grep -oE '[0-9]+' | head -1 || echo "-1")
    if [ -z "$SUMMARY_TOTAL" ]; then SUMMARY_TOTAL="-1"; fi
    
    # Extract station appearances
    for STA in TOLI GSI KWP SANI BKB; do
        if grep -q "GE.$STA:" "$SUMMARY_FILE"; then
            STATIONS_FOUND=$((STATIONS_FOUND + 1))
        fi
    done
fi

# 5. Build JSON output array
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "cfg_exists": $CFG_EXISTS,
    "cfg_trigger_on": "$CFG_TRIGGER_ON",
    "cfg_trigger_off": "$CFG_TRIGGER_OFF",
    "cfg_filter": "$CFG_FILTER",
    "cfg_time_corr": "$CFG_TIME_CORR",
    "binding_count": $BINDING_COUNT,
    "xml_exists": $([ -f "$XML_FILE" ] && echo "true" || echo "false"),
    "xml_mtime": $XML_MTIME,
    "xml_size": $XML_SIZE,
    "xml_valid": $XML_VALID,
    "xml_pick_count": $XML_PICK_COUNT,
    "summary_exists": $([ -f "$SUMMARY_FILE" ] && echo "true" || echo "false"),
    "summary_mtime": $SUMMARY_MTIME,
    "summary_size": $SUMMARY_SIZE,
    "summary_header_found": $HEADER_FOUND,
    "summary_total": $SUMMARY_TOTAL,
    "summary_stations_found": $STATIONS_FOUND
}
EOF

# Safely copy to non-root location to ensure accessibility
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="