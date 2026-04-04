#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Query the final configuration of team-virtual
echo "Fetching final repository configuration..."
API_RESULT=$(art_api GET "/api/repositories/team-virtual")

# Parse the result specifically for verification
# We need the 'repositories' list to check order
# Safe parsing with Python
PARSED_RESULT=$(echo "$API_RESULT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    # Extract relevant fields
    output = {
        'exists': True,
        'key': data.get('key'),
        'type': data.get('type', '').lower(),
        'packageType': data.get('packageType', '').lower(),
        'repositories': data.get('repositories', [])
    }
except Exception as e:
    output = {
        'exists': False, 
        'error': str(e),
        'raw': '$API_RESULT'
    }
print(json.dumps(output))
")

# Create final JSON artifact
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "config": $PARSED_RESULT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="