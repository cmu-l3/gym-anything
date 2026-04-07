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

# Check for the expected python script
SCRIPT_FILE="/home/ga/Documents/SAM_Projects/monte_carlo_lcoe.py"
SCRIPT_EXISTS="false"
SCRIPT_MODIFIED="false"
if [ -f "$SCRIPT_FILE" ]; then
    SCRIPT_EXISTS="true"
    SCRIPT_MTIME=$(stat -c%Y "$SCRIPT_FILE" 2>/dev/null || echo "0")
    if [ "$SCRIPT_MTIME" -gt "$TASK_START" ]; then
        SCRIPT_MODIFIED="true"
    fi
    PYTHON_RAN="true" # If the script exists, they at least wrote it
fi

# Check if expected JSON file exists
JSON_FILE="/home/ga/Documents/SAM_Projects/monte_carlo_results.json"
JSON_EXISTS="false"
JSON_MODIFIED="false"
ITERATIONS=0
P50_LCOE=0.0
P90_LCOE=0.0

if [ -f "$JSON_FILE" ]; then
    JSON_EXISTS="true"
    JSON_MTIME=$(stat -c%Y "$JSON_FILE" 2>/dev/null || echo "0")
    if [ "$JSON_MTIME" -gt "$TASK_START" ]; then
        JSON_MODIFIED="true"
    fi
    
    # Parse the JSON results
    if command -v jq &> /dev/null; then
        if jq empty "$JSON_FILE" 2>/dev/null; then
            ITERATIONS=$(jq -r '.iterations // 0' "$JSON_FILE" 2>/dev/null || echo "0")
            P50_LCOE=$(jq -r '.p50_lcoe_usd_per_kwh // 0.0' "$JSON_FILE" 2>/dev/null || echo "0.0")
            P90_LCOE=$(jq -r '.p90_lcoe_usd_per_kwh // 0.0' "$JSON_FILE" 2>/dev/null || echo "0.0")
        fi
    fi
fi

# Export all metrics into a single result file for the verifier
jq -n \
    --argjson script_exists "$SCRIPT_EXISTS" \
    --argjson script_modified "$SCRIPT_MODIFIED" \
    --argjson json_exists "$JSON_EXISTS" \
    --argjson json_modified "$JSON_MODIFIED" \
    --argjson python_ran "$PYTHON_RAN" \
    --arg iterations "$ITERATIONS" \
    --arg p50_lcoe "$P50_LCOE" \
    --arg p90_lcoe "$P90_LCOE" \
    --arg task_start "$TASK_START" \
    --arg task_end "$TASK_END" \
    '{
        script_exists: $script_exists,
        script_modified: $script_modified,
        json_exists: $json_exists,
        json_modified: $json_modified,
        python_ran: $python_ran,
        iterations: ($iterations | tonumber),
        p50_lcoe: ($p50_lcoe | tonumber),
        p90_lcoe: ($p90_lcoe | tonumber),
        task_start: ($task_start | tonumber),
        task_end: ($task_end | tonumber)
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="