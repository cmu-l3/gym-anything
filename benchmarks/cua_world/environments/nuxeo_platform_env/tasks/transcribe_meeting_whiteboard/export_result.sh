#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Retrieve Ground Truth
GROUND_TRUTH_CODE=$(cat /var/lib/nuxeo/ground_truth/secret_code.txt 2>/dev/null || echo "UNKNOWN")

# 2. Query Nuxeo for the Agent's Note
echo "Querying Nuxeo for Strategy Meeting Notes..."
# We search for a Note document in the Projects path with the correct title
SEARCH_QUERY="SELECT * FROM Note WHERE ecm:path STARTSWITH '/default-domain/workspaces/Projects' AND dc:title = 'Strategy Meeting Notes' AND ecm:isTrashed = 0"

# Execute NXQL query
RESPONSE=$(curl -s -u "$NUXEO_AUTH" -G \
    --data-urlencode "query=$SEARCH_QUERY" \
    "$NUXEO_URL/api/v1/search/lang/NXQL/execute")

# Extract Note details using Python
read -r NOTE_FOUND NOTE_UID NOTE_CONTENT NOTE_MODIFIED < <(echo "$RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    entries = data.get('entries', [])
    if entries:
        doc = entries[0]
        uid = doc.get('uid', '')
        props = doc.get('properties', {})
        content = props.get('note:note', '') or ''
        modified = props.get('dc:modified', '')
        print(f'true {uid} {json.dumps(content)} {modified}')
    else:
        print('false null \"\" null')
except Exception:
    print('false null \"\" null')
")

# 3. Check for Anti-Gaming (Timestamp)
# Nuxeo timestamps are ISO8601. We'll trust the fact that we deleted the note in setup.
# If NOTE_FOUND is true, it must have been created by the agent since we deleted it in setup.
WAS_CREATED_DURING_TASK="false"
if [ "$NOTE_FOUND" = "true" ]; then
    WAS_CREATED_DURING_TASK="true"
fi

# 4. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "ground_truth_code": "$GROUND_TRUTH_CODE",
    "note_found": $NOTE_FOUND,
    "note_uid": "$NOTE_UID",
    "note_content": $NOTE_CONTENT,
    "was_created_during_task": $WAS_CREATED_DURING_TASK,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="