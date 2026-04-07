#!/bin/bash
echo "=== Exporting task result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")
PYTHON_RAN="false"

if [ -f /home/ga/.bash_history ]; then
    if grep -q "python3\|python " /home/ga/.bash_history 2>/dev/null; then
        PYTHON_RAN="true"
    fi
fi

SCRIPT_FILE="/home/ga/Documents/SAM_Projects/depreciation_model.py"
SCRIPT_EXISTS="false"
if [ -f "$SCRIPT_FILE" ]; then
    SCRIPT_EXISTS="true"
    PYTHON_RAN="true"
fi

EXPECTED_FILE="/home/ga/Documents/SAM_Projects/depreciation_results.json"
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

# Extract JSON parameters
SYSTEM_SIZE="0"
TOTAL_COST="0"
NPV_MACRS="0"
NPV_SL="0"
VALUE_ADD="0"

if [ -f "$EXPECTED_FILE" ] && command -v jq &> /dev/null; then
    if jq empty "$EXPECTED_FILE" 2>/dev/null; then
        SYSTEM_SIZE=$(jq -r '.system_size_kw // "0"' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        TOTAL_COST=$(jq -r '.total_installed_cost // "0"' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        NPV_MACRS=$(jq -r '.npv_macrs_usd // "0"' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        NPV_SL=$(jq -r '.npv_straight_line_usd // "0"' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        VALUE_ADD=$(jq -r '.macrs_value_add_usd // "0"' "$EXPECTED_FILE" 2>/dev/null || echo "0")
    fi
fi

jq -n \
    --argjson file_exists "$FILE_EXISTS" \
    --argjson file_size "$FILE_SIZE" \
    --argjson file_modified "$FILE_MODIFIED" \
    --argjson script_exists "$SCRIPT_EXISTS" \
    --argjson python_ran "$PYTHON_RAN" \
    --arg system_size "$SYSTEM_SIZE" \
    --arg total_cost "$TOTAL_COST" \
    --arg npv_macrs "$NPV_MACRS" \
    --arg npv_sl "$NPV_SL" \
    --arg value_add "$VALUE_ADD" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        file_exists: $file_exists,
        file_size: $file_size,
        file_modified: $file_modified,
        script_exists: $script_exists,
        python_ran: $python_ran,
        system_size: $system_size,
        total_cost: $total_cost,
        npv_macrs: $npv_macrs,
        npv_sl: $npv_sl,
        value_add: $value_add,
        timestamp: $timestamp
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="