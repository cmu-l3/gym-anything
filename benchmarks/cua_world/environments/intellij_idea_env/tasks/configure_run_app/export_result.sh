#!/bin/bash
echo "=== Exporting configure_run_app result ==="

source /workspace/scripts/task_utils.sh

# Paths
OUTPUT_FILE="/home/ga/output/iris_filtered.json"
PROJECT_DIR="/home/ga/IdeaProjects/DataProcessor"
RUN_CONFIG_DIR="$PROJECT_DIR/.idea/runConfigurations"

# Take final screenshot
take_screenshot /tmp/task_end.png

# 1. Check Output File
OUTPUT_EXISTS="false"
OUTPUT_CONTENT=""
FILE_TIMESTAMP=0
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_CONTENT=$(cat "$OUTPUT_FILE")
    FILE_TIMESTAMP=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
fi

# 2. Check Run Configuration XML
# IntelliJ stores shared run configs in .idea/runConfigurations/Name.xml
# Local ones are in workspace.xml, but usually agents save them as shared or standard.
# We'll check the .idea directory first.
RUN_CONFIG_EXISTS="false"
RUN_CONFIG_CONTENT=""

# Check specific file first
if [ -f "$RUN_CONFIG_DIR/ProcessIrisData.xml" ]; then
    RUN_CONFIG_EXISTS="true"
    RUN_CONFIG_CONTENT=$(cat "$RUN_CONFIG_DIR/ProcessIrisData.xml")
else
    # Fallback: Check workspace.xml for the config (if stored locally)
    # This is harder to parse but we can check if string exists
    WORKSPACE_FILE="$PROJECT_DIR/.idea/workspace.xml"
    if [ -f "$WORKSPACE_FILE" ]; then
        if grep -q "ProcessIrisData" "$WORKSPACE_FILE"; then
            RUN_CONFIG_EXISTS="workspace"
            RUN_CONFIG_CONTENT="Stored in workspace.xml"
        fi
    fi
fi

# 3. Escape content for JSON safely
JSON_OUTPUT=$(echo "$OUTPUT_CONTENT" | python3 -c "import sys, json; print(json.dumps(sys.stdin.read()))")
JSON_CONFIG=$(echo "$RUN_CONFIG_CONTENT" | python3 -c "import sys, json; print(json.dumps(sys.stdin.read()))")

# 4. Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "output_exists": $OUTPUT_EXISTS,
    "output_content": $JSON_OUTPUT,
    "output_timestamp": $FILE_TIMESTAMP,
    "task_start_timestamp": $TASK_START_TIME,
    "run_config_exists": "$RUN_CONFIG_EXISTS",
    "run_config_content": $JSON_CONFIG,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="