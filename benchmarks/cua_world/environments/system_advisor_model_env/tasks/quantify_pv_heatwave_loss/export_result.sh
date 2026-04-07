#!/bin/bash
echo "=== Exporting task result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

# Anti-bypass: Check if Python was actually used during the task
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")
PYTHON_RAN="false"

if [ -f /home/ga/.bash_history ]; then
    if grep -q "python3\|python " /home/ga/.bash_history 2>/dev/null; then
        PYTHON_RAN="true"
    fi
fi

# Check if any .py files were created/modified after task start
PY_FILES=$(find /home/ga -name "*.py" -newer /home/ga/.task_start_time 2>/dev/null)
if [ -n "$PY_FILES" ]; then
    PYSAM_FOUND="false"
    for pyf in $PY_FILES; do
        if grep -ql "import PySAM\|from PySAM\|import Pvwatts\|Pvwattsv" "$pyf" 2>/dev/null; then
            PYSAM_FOUND="true"
            break
        fi
    done
    if [ "$PYSAM_FOUND" = "true" ]; then
        PYTHON_RAN="true"
    fi
fi

# Check expected outputs
EXPECTED_JSON="/home/ga/Documents/SAM_Projects/heatwave_impact.json"
EXPECTED_CSV="/home/ga/SAM_Weather_Data/phoenix_heatwave.csv"

JSON_EXISTS="false"
CSV_EXISTS="false"
JSON_MODIFIED="false"
CSV_MODIFIED="false"

if [ -f "$EXPECTED_JSON" ]; then
    JSON_EXISTS="true"
    JSON_MTIME=$(stat -c%Y "$EXPECTED_JSON" 2>/dev/null || echo "0")
    if [ "$JSON_MTIME" -gt "$TASK_START" ]; then
        JSON_MODIFIED="true"
    fi
fi

if [ -f "$EXPECTED_CSV" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c%Y "$EXPECTED_CSV" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_MODIFIED="true"
    fi
fi

# Create JSON result safely using jq
jq -n \
    --argjson json_exists "$JSON_EXISTS" \
    --argjson csv_exists "$CSV_EXISTS" \
    --argjson json_modified "$JSON_MODIFIED" \
    --argjson csv_modified "$CSV_MODIFIED" \
    --argjson python_ran "$PYTHON_RAN" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        json_exists: $json_exists,
        csv_exists: $csv_exists,
        json_modified: $json_modified,
        csv_modified: $csv_modified,
        python_ran: $python_ran,
        timestamp: $timestamp
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="