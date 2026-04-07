#!/bin/bash
# Export script for create_index_template task
echo "=== Exporting create_index_template result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TEMPLATE_NAME="wazuh-custom-alerts"
OUTPUT_FILE="/home/ga/index_template_result.json"

# 1. Query the Indexer API directly to see if the template exists and get its config
# This is the GROUND TRUTH for verification
echo "Querying Indexer for template '$TEMPLATE_NAME'..."
API_RESPONSE_FILE="/tmp/actual_template.json"
wazuh_indexer_query "/_index_template/$TEMPLATE_NAME" > "$API_RESPONSE_FILE" 2>/dev/null || true

# Check if API returned the template (simple grep check before full parsing)
if grep -q "$TEMPLATE_NAME" "$API_RESPONSE_FILE"; then
    TEMPLATE_EXISTS_IN_API="true"
else
    TEMPLATE_EXISTS_IN_API="false"
fi

# 2. Check the agent's output file
if [ -f "$OUTPUT_FILE" ]; then
    AGENT_FILE_EXISTS="true"
    AGENT_FILE_SIZE=$(stat -c %s "$OUTPUT_FILE")
    AGENT_FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    
    if [ "$AGENT_FILE_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    else
        CREATED_DURING_TASK="false"
    fi
else
    AGENT_FILE_EXISTS="false"
    AGENT_FILE_SIZE=0
    CREATED_DURING_TASK="false"
fi

# 3. Capture final screenshot
take_screenshot /tmp/task_final.png

# 4. Prepare result JSON
# We embed the raw API response content into the result JSON for Python to parse.
# We use python to escape the JSON string safely.

# Read the actual API response content
ACTUAL_TEMPLATE_CONTENT=$(cat "$API_RESPONSE_FILE" 2>/dev/null || echo "{}")

# Read the agent's file content (if exists)
AGENT_FILE_CONTENT="{}"
if [ "$AGENT_FILE_EXISTS" = "true" ]; then
    AGENT_FILE_CONTENT=$(cat "$OUTPUT_FILE" 2>/dev/null || echo "{}")
fi

# Use Python to construct valid JSON to avoid bash quoting hell
python3 -c "
import json
import os
import sys

try:
    actual_content = '''$ACTUAL_TEMPLATE_CONTENT'''
    try:
        actual_json = json.loads(actual_content)
    except:
        actual_json = {}

    agent_content = '''$AGENT_FILE_CONTENT'''
    try:
        agent_json = json.loads(agent_content)
    except:
        agent_json = {}

    result = {
        'template_exists_in_api': '$TEMPLATE_EXISTS_IN_API' == 'true',
        'actual_template_config': actual_json,
        'agent_file_exists': '$AGENT_FILE_EXISTS' == 'true',
        'agent_file_created_during_task': '$CREATED_DURING_TASK' == 'true',
        'agent_file_content': agent_json,
        'screenshot_path': '/tmp/task_final.png'
    }
    
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f)

except Exception as e:
    print(f'Error creating result JSON: {e}', file=sys.stderr)
"

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="