#!/bin/bash
echo "=== Exporting task result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Check timestamps
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")
PYTHON_RAN="false"

# Look for evidence of python execution in bash history
if [ -f /home/ga/.bash_history ]; then
    if grep -q "python3\|python " /home/ga/.bash_history 2>/dev/null; then
        PYTHON_RAN="true"
    fi
fi

# Check if any .py files were created/modified
PY_FILES=$(find /home/ga -name "*.py" -newer /home/ga/.task_start_time 2>/dev/null)
if [ -n "$PY_FILES" ]; then
    # Look for PySAM Windpower imports
    for pyf in $PY_FILES; do
        if grep -ql "import PySAM\|from PySAM" "$pyf" 2>/dev/null; then
            PYTHON_RAN="true"
            break
        fi
    done
fi

EXPECTED_FILE="/home/ga/Documents/SAM_Projects/wind_farm_wake_analysis.json"

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

# Create a summary JSON for the verifier (verifier will copy the actual JSON file too)
cat > /tmp/task_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_modified": $FILE_MODIFIED,
    "python_ran": $PYTHON_RAN,
    "task_start": $TASK_START,
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Summary exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="