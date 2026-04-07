#!/bin/bash
echo "=== Exporting task result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

# Anti-bypass: Check if Python or SAM was actually used during the task
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")
PYTHON_RAN="false"
SAM_USED="false"

# Check bash history for python3 commands
if [ -f /home/ga/.bash_history ]; then
    if grep -q "python3\|python " /home/ga/.bash_history 2>/dev/null; then
        PYTHON_RAN="true"
    fi
fi

# Check if any .py or .sam files were created/modified after task start
PY_FILES=$(find /home/ga -name "*.py" -newer /home/ga/.task_start_time 2>/dev/null)
if [ -n "$PY_FILES" ]; then
    for pyf in $PY_FILES; do
        if grep -ql "import PySAM\|from PySAM" "$pyf" 2>/dev/null; then
            PYTHON_RAN="true"
            break
        fi
    done
fi

SAM_FILES=$(find /home/ga/Documents -name "*.sam" -newer /home/ga/.task_start_time 2>/dev/null)
if [ -n "$SAM_FILES" ]; then
    SAM_USED="true"
fi

# Determine if some valid artifact exists indicating work
ARTIFACTS_EXIST="false"
if [ "$PYTHON_RAN" = "true" ] || [ "$SAM_USED" = "true" ]; then
    ARTIFACTS_EXIST="true"
fi

# Check if expected output file exists
EXPECTED_FILE="/home/ga/Documents/SAM_Projects/battery_degradation_report.json"

FILE_EXISTS="false"
FILE_SIZE=0
FILE_MODIFIED="false"

if [ -f "$EXPECTED_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$EXPECTED_FILE" 2>/dev/null || echo "0")
    
    FILE_MTIME=$(stat -c%Y "$EXPECTED_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Create JSON result safely using jq
jq -n \
    --argjson file_exists "$FILE_EXISTS" \
    --argjson file_size "$FILE_SIZE" \
    --argjson file_modified "$FILE_MODIFIED" \
    --argjson artifacts_exist "$ARTIFACTS_EXIST" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        file_exists: $file_exists,
        file_size: $file_size,
        file_modified: $file_modified,
        artifacts_exist: $artifacts_exist,
        timestamp: $timestamp
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="