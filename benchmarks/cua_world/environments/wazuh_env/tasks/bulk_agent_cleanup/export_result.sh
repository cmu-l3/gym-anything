#!/bin/bash
echo "=== Exporting Bulk Agent Cleanup Results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query current agents via API
echo "Querying agent inventory..."
AGENTS_JSON=$(wazuh_api GET "/agents?limit=500&select=id,name,status")

# Save raw JSON for debugging
echo "$AGENTS_JSON" > /tmp/agents_raw.json

# Parse relevant data for verification
# We need: total count, list of names present
PARSED_RESULT=$(python3 <<EOF
import sys, json

try:
    with open('/tmp/agents_raw.json', 'r') as f:
        data = json.load(f)
    
    items = data.get('data', {}).get('affected_items', [])
    
    agent_names = [item.get('name') for item in items]
    agent_ids = [item.get('id') for item in items]
    total_count = data.get('data', {}).get('total_affected_items', 0)
    
    result = {
        "agent_names": agent_names,
        "agent_ids": agent_ids,
        "total_count": total_count,
        "api_success": True
    }
except Exception as e:
    result = {
        "error": str(e),
        "api_success": False,
        "agent_names": [],
        "total_count": 0
    }

print(json.dumps(result))
EOF
)

# Prepare final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "inventory": $PARSED_RESULT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export Complete ==="