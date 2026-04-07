#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DOC_ID=$(cat /tmp/target_doc_id.txt 2>/dev/null || echo "")
INITIAL_WORKFLOW_ID=$(cat /tmp/initial_workflow_id.txt 2>/dev/null || echo "")

echo "Verifying state for Doc ID: $DOC_ID"

# 1. Check if Document Still Exists
DOC_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/id/$DOC_ID")
if [ "$DOC_STATUS" = "200" ]; then
    DOC_EXISTS="true"
else
    DOC_EXISTS="false"
fi

# 2. Check for Active Tasks on the Document
# We query for tasks targeting this document that are NOT completed
ACTIVE_TASKS_COUNT=0
TASKS_JSON=$(nuxeo_api GET "/task?targetDocumentId=$DOC_ID&isCompleted=false")
ACTIVE_TASKS_COUNT=$(echo "$TASKS_JSON" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('entries',[])))" 2>/dev/null || echo "0")

# 3. Check specific Workflow Instance State (if we have the ID)
WORKFLOW_STATE="unknown"
if [ -n "$INITIAL_WORKFLOW_ID" ]; then
    # If workflow is cancelled/ended, it might be 404 or have state 'canceled'/'ended'
    WF_JSON=$(nuxeo_api GET "/workflow/$INITIAL_WORKFLOW_ID")
    WF_STATE=$(echo "$WF_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('state','missing'))" 2>/dev/null)
    WORKFLOW_STATE="$WF_STATE"
fi

# 4. Take final screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 5. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "document_exists": $DOC_EXISTS,
    "active_tasks_count": $ACTIVE_TASKS_COUNT,
    "workflow_state": "$WORKFLOW_STATE",
    "initial_workflow_id": "$INITIAL_WORKFLOW_ID",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="