#!/bin/bash
echo "=== Exporting task result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

PY_FILE="/home/ga/Documents/SAM_Projects/hub_height_analysis.py"
JSON_FILE="/home/ga/Documents/SAM_Projects/hub_height_results.json"

PY_EXISTS="false"
JSON_EXISTS="false"
JSON_MODIFIED="false"
PY_CONTAINS_PYSAM="false"
PY_CONTAINS_EXECUTE="false"
RESOURCE_FILE_VALID="false"

# Check Python script existence and contents (Anti-gaming: ensure PySAM and execute are used)
if [ -f "$PY_FILE" ]; then
    PY_EXISTS="true"
    if grep -q "PySAM.Windpower\|import PySAM" "$PY_FILE"; then
        PY_CONTAINS_PYSAM="true"
    fi
    if grep -q "\.execute()" "$PY_FILE"; then
        PY_CONTAINS_EXECUTE="true"
    fi
fi

AEP_80="0"
AEP_100="0"
PERCENT_INC="0"
RESOURCE_FILE=""

# Parse JSON results if file exists
if [ -f "$JSON_FILE" ]; then
    JSON_EXISTS="true"
    JSON_MTIME=$(stat -c%Y "$JSON_FILE" 2>/dev/null || echo "0")
    if [ "$JSON_MTIME" -gt "$TASK_START" ]; then
        JSON_MODIFIED="true"
    fi
    
    if command -v jq &> /dev/null; then
        AEP_80=$(jq -r '.aep_80m_kwh // "0"' "$JSON_FILE" 2>/dev/null || echo "0")
        AEP_100=$(jq -r '.aep_100m_kwh // "0"' "$JSON_FILE" 2>/dev/null || echo "0")
        PERCENT_INC=$(jq -r '.percent_increase // "0"' "$JSON_FILE" 2>/dev/null || echo "0")
        RESOURCE_FILE=$(jq -r '.resource_file_used // ""' "$JSON_FILE" 2>/dev/null || echo "")
    fi
    
    # Check if resource file actually exists on the system and is a wind resource file
    if [ -n "$RESOURCE_FILE" ] && [ -f "$RESOURCE_FILE" ] && [[ "$RESOURCE_FILE" == *".srw" ]]; then
        RESOURCE_FILE_VALID="true"
    fi
fi

# Create structured JSON result safely using jq
jq -n \
    --argjson py_exists "$PY_EXISTS" \
    --argjson json_exists "$JSON_EXISTS" \
    --argjson json_modified "$JSON_MODIFIED" \
    --argjson py_contains_pysam "$PY_CONTAINS_PYSAM" \
    --argjson py_contains_execute "$PY_CONTAINS_EXECUTE" \
    --argjson resource_file_valid "$RESOURCE_FILE_VALID" \
    --arg aep_80 "$AEP_80" \
    --arg aep_100 "$AEP_100" \
    --arg percent_inc "$PERCENT_INC" \
    --arg resource_file "$RESOURCE_FILE" \
    '{
        py_exists: $py_exists,
        json_exists: $json_exists,
        json_modified: $json_modified,
        py_contains_pysam: $py_contains_pysam,
        py_contains_execute: $py_contains_execute,
        resource_file_valid: $resource_file_valid,
        aep_80: $aep_80,
        aep_100: $aep_100,
        percent_inc: $percent_inc,
        resource_file: $resource_file
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="