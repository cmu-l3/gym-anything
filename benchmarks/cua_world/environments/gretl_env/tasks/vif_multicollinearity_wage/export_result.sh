#!/bin/bash
echo "=== Exporting VIF Multicollinearity Wage task results ==="
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_DIR="/home/ga/Documents/gretl_output"
SCRIPT_FILE="$OUTPUT_DIR/vif_analysis.inp"
MODEL_FILE="$OUTPUT_DIR/wage_model.txt"
VIF_FILE="$OUTPUT_DIR/vif_results.txt"

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Check files existence and timestamps
check_file() {
    local file="$1"
    if [ -f "$file" ]; then
        local mtime=$(stat -c %Y "$file")
        if [ "$mtime" -gt "$TASK_START" ]; then
            echo "true"
        else
            echo "pre-existing"
        fi
    else
        echo "false"
    fi
}

SCRIPT_STATUS=$(check_file "$SCRIPT_FILE")
MODEL_STATUS=$(check_file "$MODEL_FILE")
VIF_STATUS=$(check_file "$VIF_FILE")

# 3. Validate Script Execution (Programmatic Check)
# Try to run the agent's script to see if it works and matches expected output
SCRIPT_VALID="false"
SCRIPT_OUTPUT=""
SCRIPT_ERROR=""

if [ "$SCRIPT_STATUS" != "false" ]; then
    echo "Validating agent script execution..."
    # Run in a temp location to avoid overwriting agent's output files
    su - ga -c "gretlcli -b '$SCRIPT_FILE'" > /tmp/agent_script_run.log 2>&1
    RET_CODE=$?
    
    if [ $RET_CODE -eq 0 ]; then
        SCRIPT_VALID="true"
        # Read the output log
        SCRIPT_OUTPUT=$(cat /tmp/agent_script_run.log | head -n 500 | base64 -w 0)
    else
        SCRIPT_VALID="false"
        SCRIPT_ERROR="Exit code $RET_CODE"
        SCRIPT_OUTPUT=$(cat /tmp/agent_script_run.log | tail -n 20 | base64 -w 0)
    fi
fi

# 4. Read file contents for content verification
read_file_content() {
    local file="$1"
    if [ -f "$file" ]; then
        cat "$file" | head -n 100 | base64 -w 0
    else
        echo ""
    fi
}

MODEL_CONTENT=$(read_file_content "$MODEL_FILE")
VIF_CONTENT=$(read_file_content "$VIF_FILE")

# 5. Get Ground Truth for Comparison
EXPECTED_OUTPUT=$(cat /tmp/ground_truth/expected_output.txt 2>/dev/null | base64 -w 0)

# 6. Check if Gretl is running
APP_RUNNING="false"
if is_gretl_running; then
    APP_RUNNING="true"
fi

# 7. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "files": {
        "script": {
            "exists": $([ "$SCRIPT_STATUS" != "false" ] && echo "true" || echo "false"),
            "created_during_task": $([ "$SCRIPT_STATUS" == "true" ] && echo "true" || echo "false"),
            "valid_execution": $SCRIPT_VALID,
            "execution_log_b64": "$SCRIPT_OUTPUT",
            "error": "$SCRIPT_ERROR"
        },
        "model_output": {
            "exists": $([ "$MODEL_STATUS" != "false" ] && echo "true" || echo "false"),
            "created_during_task": $([ "$MODEL_STATUS" == "true" ] && echo "true" || echo "false"),
            "content_b64": "$MODEL_CONTENT"
        },
        "vif_output": {
            "exists": $([ "$VIF_STATUS" != "false" ] && echo "true" || echo "false"),
            "created_during_task": $([ "$VIF_STATUS" == "true" ] && echo "true" || echo "false"),
            "content_b64": "$VIF_CONTENT"
        }
    },
    "ground_truth_b64": "$EXPECTED_OUTPUT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move and sanitize
chmod 644 "$TEMP_JSON"
mv "$TEMP_JSON" /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="