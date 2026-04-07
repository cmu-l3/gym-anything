#!/bin/bash
echo "=== Exporting Asset Inventory Results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Collect timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Check Agent Output File
OUTPUT_PATH="/home/ga/Documents/system_inventory.json"
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
AGENT_CONTENT="{}"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if created/modified after start time
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Read content (limit size to prevent massive log injection)
    # Using python to safely read JSON or partial content
    AGENT_CONTENT=$(python3 -c "
import json, sys
try:
    with open('$OUTPUT_PATH', 'r') as f:
        # Read max 1MB
        data = f.read(1000000)
        # Try to parse to ensure it's valid JSON, otherwise treat as text
        obj = json.loads(data)
        print(json.dumps(obj))
except Exception as e:
    print(json.dumps({'error': 'Invalid JSON', 'raw': str(e)}))
" 2>/dev/null)
fi

# 4. Capture Ground Truth (Live State)
# We query the API *now* to compare against what the agent found
echo "Capturing ground truth from API..."
TOKEN=$(get_nx_token)

SYSTEM_INFO=$(curl -sk -H "Authorization: Bearer $TOKEN" "https://localhost:7001/rest/v1/system/info" 2>/dev/null || echo "{}")
SERVERS=$(curl -sk -H "Authorization: Bearer $TOKEN" "https://localhost:7001/rest/v1/servers" 2>/dev/null || echo "[]")
CAMERAS=$(curl -sk -H "Authorization: Bearer $TOKEN" "https://localhost:7001/rest/v1/devices" 2>/dev/null || echo "[]")
USERS=$(curl -sk -H "Authorization: Bearer $TOKEN" "https://localhost:7001/rest/v1/users" 2>/dev/null || echo "[]")
LAYOUTS=$(curl -sk -H "Authorization: Bearer $TOKEN" "https://localhost:7001/rest/v1/layouts" 2>/dev/null || echo "[]")

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "meta": {
        "task_start": $TASK_START,
        "task_end": $TASK_END,
        "output_exists": $OUTPUT_EXISTS,
        "file_created_during_task": $FILE_CREATED_DURING_TASK,
        "screenshot_path": "/tmp/task_final.png"
    },
    "agent_output": $AGENT_CONTENT,
    "ground_truth": {
        "system": $SYSTEM_INFO,
        "servers": $SERVERS,
        "cameras": $CAMERAS,
        "users": $USERS,
        "layouts": $LAYOUTS
    }
}
EOF

# 6. Save to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"