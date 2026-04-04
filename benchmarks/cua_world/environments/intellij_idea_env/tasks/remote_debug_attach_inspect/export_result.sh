#!/bin/bash
echo "=== Exporting Remote Debug Result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/PaymentGateway"
OUTPUT_FILE="$PROJECT_DIR/token_found.txt"
GROUND_TRUTH_FILE="/tmp/.ground_truth_token"

# Take final screenshot (critical for VLM verification of debugger state)
take_screenshot /tmp/task_end.png

# 1. Check if output file exists
OUTPUT_EXISTS="false"
OUTPUT_CONTENT=""
if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_CONTENT=$(cat "$OUTPUT_FILE" | tr -d '\n\r ')
fi

# 2. Check if run configurations were created
# IntelliJ stores shared run configs in .idea/runConfigurations or workspace.xml
# We check for the presence of "Remote" type configuration files or entries
RUN_CONFIG_EXISTS="false"
if [ -d "$PROJECT_DIR/.idea/runConfigurations" ]; then
    if grep -r "Remote" "$PROJECT_DIR/.idea/runConfigurations" >/dev/null 2>&1; then
        RUN_CONFIG_EXISTS="true"
    fi
fi
# Also check workspace.xml (user specific configs)
if [ -f "$PROJECT_DIR/.idea/workspace.xml" ]; then
    if grep -q "Remote" "$PROJECT_DIR/.idea/workspace.xml"; then
        RUN_CONFIG_EXISTS="true"
    fi
fi

# 3. Check if background process is still running or was running
PROCESS_RUNNING="false"
if pgrep -f "TransactionProcessor" > /dev/null; then
    PROCESS_RUNNING="true"
fi

# 4. Get Ground Truth (hidden from agent)
GROUND_TRUTH=""
if [ -f "$GROUND_TRUTH_FILE" ]; then
    GROUND_TRUTH=$(cat "$GROUND_TRUTH_FILE")
fi

# 5. Check if output matches ground truth
TOKEN_MATCH="false"
if [ "$OUTPUT_EXISTS" = "true" ] && [ -n "$GROUND_TRUTH" ]; then
    if [ "$OUTPUT_CONTENT" = "$GROUND_TRUTH" ]; then
        TOKEN_MATCH="true"
    fi
fi

# Create JSON result
RESULT_JSON=$(cat << EOF
{
    "output_exists": $OUTPUT_EXISTS,
    "output_content": "$OUTPUT_CONTENT",
    "ground_truth": "$GROUND_TRUTH",
    "token_match": $TOKEN_MATCH,
    "run_config_exists": $RUN_CONFIG_EXISTS,
    "process_running": $PROCESS_RUNNING,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="