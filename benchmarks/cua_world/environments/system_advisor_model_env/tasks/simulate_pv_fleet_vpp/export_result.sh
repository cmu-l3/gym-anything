#!/bin/bash
echo "=== Exporting task result ==="

# Record task end time
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Track Python Usage
PYTHON_RAN="false"
if grep -q "python3\|python " /home/ga/.bash_history 2>/dev/null; then
    PYTHON_RAN="true"
fi

# Track Python Script Existence & Content
SCRIPT_EXISTS="false"
SCRIPT_CONTAINS_PYSAM="false"
SCRIPT_FILE="/home/ga/Documents/SAM_Projects/vpp_simulation.py"

if [ -f "$SCRIPT_FILE" ]; then
    SCRIPT_EXISTS="true"
    if grep -ql "import PySAM\|from PySAM\|import Pvwatts\|Pvwattsv" "$SCRIPT_FILE" 2>/dev/null; then
        SCRIPT_CONTAINS_PYSAM="true"
        PYTHON_RAN="true" # Implies intention to use PySAM
    fi
fi

# Check expected JSON output
JSON_FILE="/home/ga/Documents/SAM_Projects/vpp_fleet_results.json"
JSON_EXISTS="false"
JSON_SIZE="0"
JSON_MODIFIED="false"

if [ -f "$JSON_FILE" ]; then
    JSON_EXISTS="true"
    JSON_SIZE=$(stat -c%s "$JSON_FILE" 2>/dev/null || echo "0")
    
    FILE_MTIME=$(stat -c%Y "$JSON_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        JSON_MODIFIED="true"
    fi
fi

# Write minimal metadata to task_result.json
# We leave deep validation of the JSON to the Python verifier using copy_from_env
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "python_ran": $PYTHON_RAN,
    "script_exists": $SCRIPT_EXISTS,
    "script_contains_pysam": $SCRIPT_CONTAINS_PYSAM,
    "json_exists": $JSON_EXISTS,
    "json_size_bytes": $JSON_SIZE,
    "json_modified_during_task": $JSON_MODIFIED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move securely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="