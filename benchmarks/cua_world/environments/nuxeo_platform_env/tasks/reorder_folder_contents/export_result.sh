#!/bin/bash
echo "=== Exporting Reorder Folder Contents Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Query the children of the folder via API
# The @children adapter on an OrderedFolder returns items in their specific order
echo "Querying folder children..."
FOLDER_PATH="/default-domain/workspaces/Projects/Onboarding-Checklist"
CHILDREN_JSON=$(curl -s -u "$NUXEO_AUTH" \
    -H "Content-Type: application/json" \
    "$NUXEO_URL/api/v1/path$FOLDER_PATH/@children")

# 3. Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_path": "/tmp/task_final.png",
    "folder_children": $CHILDREN_JSON
}
EOF

# Move to standard location with safe permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="