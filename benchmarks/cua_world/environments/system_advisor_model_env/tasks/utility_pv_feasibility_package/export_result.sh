#!/bin/bash
echo "=== Exporting utility_pv_feasibility_package task result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Anti-bypass: Check if Python was actually used during the task
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")
PYTHON_RAN="false"

if [ -f /home/ga/.bash_history ]; then
    if grep -q "python3\|python " /home/ga/.bash_history 2>/dev/null; then
        PYTHON_RAN="true"
    fi
fi

# Check if any .py files were created/modified after task start AND contain PySAM imports
PY_FILES=$(find /home/ga -name "*.py" -newer /home/ga/.task_start_time 2>/dev/null)
if [ -n "$PY_FILES" ]; then
    for pyf in $PY_FILES; do
        if grep -ql "import PySAM\|from PySAM\|Pvwattsv\|Singleowner" "$pyf" 2>/dev/null; then
            PYTHON_RAN="true"
            break
        fi
    done
fi

# Check if expected output file exists
EXPECTED_FILE="/home/ga/Documents/SAM_Projects/phoenix_feasibility_package.json"

FILE_EXISTS="false"
FILE_SIZE="0"
FILE_MODIFIED="false"

if [ -f "$EXPECTED_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$EXPECTED_FILE" 2>/dev/null || echo "0")

    FILE_MTIME=$(stat -c%Y "$EXPECTED_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Check for top-level JSON structure keys
HAS_SYSTEM_DESIGN="false"
HAS_FINANCIAL="false"
HAS_SENSITIVITY="false"

if [ "$FILE_EXISTS" = "true" ] && command -v jq &> /dev/null; then
    if jq empty "$EXPECTED_FILE" 2>/dev/null; then
        if jq -e '.system_design' "$EXPECTED_FILE" > /dev/null 2>&1; then
            HAS_SYSTEM_DESIGN="true"
        fi
        if jq -e '.financial_analysis' "$EXPECTED_FILE" > /dev/null 2>&1; then
            HAS_FINANCIAL="true"
        fi
        if jq -e '.sensitivity_analysis' "$EXPECTED_FILE" > /dev/null 2>&1; then
            HAS_SENSITIVITY="true"
        fi
    fi
fi

# Build result JSON
jq -n \
    --argjson file_exists "$FILE_EXISTS" \
    --argjson file_size "$FILE_SIZE" \
    --argjson file_modified "$FILE_MODIFIED" \
    --argjson python_ran "$PYTHON_RAN" \
    --argjson has_system_design "$HAS_SYSTEM_DESIGN" \
    --argjson has_financial "$HAS_FINANCIAL" \
    --argjson has_sensitivity "$HAS_SENSITIVITY" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        file_exists: $file_exists,
        file_size: $file_size,
        file_modified: $file_modified,
        python_ran: $python_ran,
        has_system_design: $has_system_design,
        has_financial_analysis: $has_financial,
        has_sensitivity_analysis: $has_sensitivity,
        timestamp: $timestamp
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
