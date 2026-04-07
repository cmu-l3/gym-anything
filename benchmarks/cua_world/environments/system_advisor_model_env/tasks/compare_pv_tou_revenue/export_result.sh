#!/bin/bash
echo "=== Exporting task result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")
PYTHON_RAN="false"

# Check bash history for python3 commands
if [ -f /home/ga/.bash_history ]; then
    if grep -q "python3\|python " /home/ga/.bash_history 2>/dev/null; then
        PYTHON_RAN="true"
    fi
fi

EXPECTED_SCRIPT="/home/ga/Documents/SAM_Projects/tou_analysis.py"
EXPECTED_JSON="/home/ga/Documents/SAM_Projects/tou_results.json"

SCRIPT_EXISTS="false"
SCRIPT_MODIFIED="false"
JSON_EXISTS="false"
JSON_MODIFIED="false"
AGENT_JSON_CONTENT="{}"

if [ -f "$EXPECTED_SCRIPT" ]; then
    SCRIPT_EXISTS="true"
    SCRIPT_MTIME=$(stat -c%Y "$EXPECTED_SCRIPT" 2>/dev/null || echo "0")
    if [ "$SCRIPT_MTIME" -gt "$TASK_START" ]; then
        SCRIPT_MODIFIED="true"
    fi
    # If the script contains PySAM imports, mark python_ran as true
    if grep -ql "import PySAM\|from PySAM\|import Pvwatts\|Pvwattsv" "$EXPECTED_SCRIPT" 2>/dev/null; then
        PYTHON_RAN="true"
    fi
fi

if [ -f "$EXPECTED_JSON" ]; then
    JSON_EXISTS="true"
    JSON_MTIME=$(stat -c%Y "$EXPECTED_JSON" 2>/dev/null || echo "0")
    if [ "$JSON_MTIME" -gt "$TASK_START" ]; then
        JSON_MODIFIED="true"
    fi
    # Safely extract the JSON contents
    if command -v jq &> /dev/null && jq empty "$EXPECTED_JSON" 2>/dev/null; then
        AGENT_JSON_CONTENT=$(jq -c . "$EXPECTED_JSON" 2>/dev/null)
    else
        # If it's invalid JSON, just pass empty object to fail gracefully in Python
        AGENT_JSON_CONTENT="{}"
    fi
fi

# Create JSON result safely using jq
jq -n \
    --argjson script_exists "$SCRIPT_EXISTS" \
    --argjson script_modified "$SCRIPT_MODIFIED" \
    --argjson json_exists "$JSON_EXISTS" \
    --argjson json_modified "$JSON_MODIFIED" \
    --argjson python_ran "$PYTHON_RAN" \
    --argjson agent_json_content "${AGENT_JSON_CONTENT:-{}}" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        script_exists: $script_exists,
        script_modified: $script_modified,
        json_exists: $json_exists,
        json_modified: $json_modified,
        python_ran: $python_ran,
        agent_json_content: $agent_json_content,
        timestamp: $timestamp
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="