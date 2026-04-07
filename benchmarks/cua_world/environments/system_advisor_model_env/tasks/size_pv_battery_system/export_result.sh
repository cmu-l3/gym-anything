#!/bin/bash
echo "=== Exporting task result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

# 1. Check Python Usage
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")
PYTHON_RAN="false"

if [ -f /home/ga/.bash_history ]; then
    if grep -q "python3\|python " /home/ga/.bash_history 2>/dev/null; then
        PYTHON_RAN="true"
    fi
fi

# Check for .py files referencing PySAM
PY_FILES=$(find /home/ga -name "*.py" -newer /home/ga/.task_start_time 2>/dev/null)
if [ -n "$PY_FILES" ]; then
    for pyf in $PY_FILES; do
        if grep -ql "PySAM" "$pyf" 2>/dev/null; then
            PYTHON_RAN="true"
            break
        fi
    done
fi

# 2. Check File Metadata
EXPECTED_FILE="/home/ga/Documents/SAM_Projects/pv_battery_report.json"
FILE_EXISTS="false"
FILE_MODIFIED="false"

if [ -f "$EXPECTED_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c%Y "$EXPECTED_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    
    # Check if the weather file referenced in the JSON actually exists
    WEATHER_FILE=$(jq -r '.system_config.weather_file // empty' "$EXPECTED_FILE" 2>/dev/null || echo "")
    WEATHER_FILE_EXISTS="false"
    if [ -n "$WEATHER_FILE" ] && [ -f "$WEATHER_FILE" ]; then
        WEATHER_FILE_EXISTS="true"
    fi
else
    WEATHER_FILE_EXISTS="false"
fi

# Create result JSON
jq -n \
    --argjson file_exists "$FILE_EXISTS" \
    --argjson file_modified "$FILE_MODIFIED" \
    --argjson python_ran "$PYTHON_RAN" \
    --argjson weather_file_exists "$WEATHER_FILE_EXISTS" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        file_exists: $file_exists,
        file_modified: $file_modified,
        python_ran: $python_ran,
        weather_file_exists: $weather_file_exists,
        timestamp: $timestamp
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result metadata saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="