#!/bin/bash
echo "=== Exporting task result ==="

# Record task end time
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if Python was actually used during the task
PYTHON_RAN="false"
if [ -f /home/ga/.bash_history ]; then
    if grep -q "python3\|python " /home/ga/.bash_history 2>/dev/null; then
        PYTHON_RAN="true"
    fi
fi

# Check for .py files created during the task that contain PySAM imports
PY_FILES=$(find /home/ga -name "*.py" -newer /home/ga/.task_start_time 2>/dev/null)
if [ -n "$PY_FILES" ]; then
    for pyf in $PY_FILES; do
        if grep -ql "import PySAM\|from PySAM\|Pvwattsv\|Pvwatts" "$pyf" 2>/dev/null; then
            PYTHON_RAN="true"
            break
        fi
    done
fi

# Check if expected JSON output file exists
JSON_FILE="/home/ga/Documents/SAM_Projects/curtailment_battery_optimization.json"
JSON_EXISTS="false"
JSON_MODIFIED="false"
IS_VALID_JSON="false"

# Initialize extracted values
PV_GEN="0"
NO_BATT_REVENUE="0"
NO_BATT_CURTAILED="0"
NUM_SCENARIOS="0"
OPTIMAL_CAP="0"

if [ -f "$JSON_FILE" ]; then
    JSON_EXISTS="true"

    FILE_MTIME=$(stat -c%Y "$JSON_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        JSON_MODIFIED="true"
    fi

    # Try parsing the JSON and extracting key values
    if command -v jq &> /dev/null; then
        if jq empty "$JSON_FILE" 2>/dev/null; then
            IS_VALID_JSON="true"

            PV_GEN=$(jq -r '.pv_generation_before_curtailment_mwh // 0' "$JSON_FILE" 2>/dev/null)
            NO_BATT_REVENUE=$(jq -r '.no_battery_revenue_dollars // 0' "$JSON_FILE" 2>/dev/null)
            NO_BATT_CURTAILED=$(jq -r '.no_battery_curtailed_mwh // 0' "$JSON_FILE" 2>/dev/null)
            NUM_SCENARIOS=$(jq -r '.battery_scenarios | length // 0' "$JSON_FILE" 2>/dev/null)
            OPTIMAL_CAP=$(jq -r '.optimal_capacity_mwh // 0' "$JSON_FILE" 2>/dev/null)
        fi
    fi
fi

# Create result JSON for verifier
jq -n \
    --argjson json_exists "$JSON_EXISTS" \
    --argjson json_modified "$JSON_MODIFIED" \
    --argjson is_valid_json "$IS_VALID_JSON" \
    --argjson python_ran "$PYTHON_RAN" \
    --arg pv_gen "$PV_GEN" \
    --arg no_batt_revenue "$NO_BATT_REVENUE" \
    --arg no_batt_curtailed "$NO_BATT_CURTAILED" \
    --arg num_scenarios "$NUM_SCENARIOS" \
    --arg optimal_cap "$OPTIMAL_CAP" \
    --arg task_start "$TASK_START" \
    --arg task_end "$TASK_END" \
    '{
        json_exists: $json_exists,
        json_modified: $json_modified,
        is_valid_json: $is_valid_json,
        python_ran: $python_ran,
        pv_gen: ($pv_gen | tonumber),
        no_batt_revenue: ($no_batt_revenue | tonumber),
        no_batt_curtailed: ($no_batt_curtailed | tonumber),
        num_scenarios: ($num_scenarios | tonumber),
        optimal_cap: ($optimal_cap | tonumber),
        task_start: ($task_start | tonumber),
        task_end: ($task_end | tonumber)
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
