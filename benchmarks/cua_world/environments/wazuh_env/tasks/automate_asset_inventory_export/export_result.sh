#!/bin/bash
echo "=== Exporting automate_asset_inventory_export result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

SCRIPT_PATH="/home/ga/agent_reporter.py"
CSV_PATH="/home/ga/active_agents.csv"
VERIFICATION_CSV="/tmp/verification_run.csv"
LOG_FILE="/tmp/script_execution.log"

# 1. Check if script exists and was created/modified during task
SCRIPT_EXISTS="false"
SCRIPT_VALID="false"
SCRIPT_CREATED_DURING="false"

if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    MTIME=$(stat -c %Y "$SCRIPT_PATH")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        SCRIPT_CREATED_DURING="true"
    fi
    
    # 2. Functional Test: Run the agent's script to see if it works
    # We rename the output file in the script or move the result after?
    # Since we can't easily change the script's output path without editing it,
    # we'll delete the existing CSV, run the script, and check if CSV regenerates.
    
    echo "Running functional verification of agent script..." > "$LOG_FILE"
    
    # Backup existing CSV if it exists
    if [ -f "$CSV_PATH" ]; then
        mv "$CSV_PATH" "${CSV_PATH}.bak"
    fi
    
    # Execute script as user ga
    if su - ga -c "python3 $SCRIPT_PATH" >> "$LOG_FILE" 2>&1; then
        echo "Script execution completed with exit code 0" >> "$LOG_FILE"
        if [ -f "$CSV_PATH" ]; then
            SCRIPT_VALID="true"
            cp "$CSV_PATH" "$VERIFICATION_CSV"
        else
            echo "Script ran but did not generate $CSV_PATH" >> "$LOG_FILE"
        fi
    else
        echo "Script execution failed" >> "$LOG_FILE"
    fi
    
    # Restore backup so we can also analyze what the agent produced manually
    if [ -f "${CSV_PATH}.bak" ]; then
        # If script generated a new one, move it to 'agent_generated' for separate analysis if needed
        # But for now, let's just keep the one we just verified or restore the old one if failed
        if [ -f "$CSV_PATH" ]; then
            # We have a verified run output
            :
        else
            mv "${CSV_PATH}.bak" "$CSV_PATH"
        fi
    fi
fi

# 3. Check CSV Output (The one currently on disk)
CSV_EXISTS="false"
CSV_CONTENT=""
CSV_HEADERS=""

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    # Read headers (first line)
    CSV_HEADERS=$(head -n 1 "$CSV_PATH")
    # Read content (first 5 lines)
    CSV_CONTENT=$(head -n 5 "$CSV_PATH")
fi

# 4. Get Ground Truth (API Query for comparison)
GROUND_TRUTH=""
TOKEN=$(get_api_token)
if [ -n "$TOKEN" ]; then
    GROUND_TRUTH=$(curl -sk -X GET "${WAZUH_API_URL}/agents?status=active&select=id,name,ip,os.name,group" \
        -H "Authorization: Bearer ${TOKEN}")
fi

# 5. Take final screenshot
take_screenshot /tmp/task_final.png

# 6. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "script_exists": $SCRIPT_EXISTS,
    "script_created_during_task": $SCRIPT_CREATED_DURING,
    "script_valid_execution": $SCRIPT_VALID,
    "csv_exists": $CSV_EXISTS,
    "csv_headers": "$(echo "$CSV_HEADERS" | sed 's/"/\\"/g')",
    "csv_content_sample": "$(echo "$CSV_CONTENT" | sed 's/"/\\"/g' | tr '\n' ';')",
    "ground_truth_json": $(echo "$GROUND_TRUTH" | jq -c . 2>/dev/null || echo "{}"),
    "execution_log": "$(cat "$LOG_FILE" | sed 's/"/\\"/g' | tr '\n' ';')"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"