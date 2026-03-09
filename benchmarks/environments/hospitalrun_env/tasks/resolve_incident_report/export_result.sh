#!/bin/bash
echo "=== Exporting resolve_incident_report result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/resolve_incident_final.png

# 2. Extract Data from CouchDB
# We need to fetch the target incident specifically to check its status and content
TARGET_ID="incident_p1_000001"
TARGET_DOC=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${TARGET_ID}")

# Fetch all incidents to check for duplicates or new creations (anti-gaming)
ALL_INCIDENTS=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" | \
    python3 -c "
import sys, json
data = json.load(sys.stdin)
incidents = []
for row in data.get('rows', []):
    doc = row.get('doc', {})
    if doc.get('type') == 'incident' or 'incident' in row.get('id', ''):
        incidents.append({
            'id': row.get('id'),
            'data': doc.get('data', {})
        })
print(json.dumps(incidents))
")

# 3. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_doc": $TARGET_DOC,
    "all_incidents": $ALL_INCIDENTS,
    "task_end_time": $(date +%s),
    "screenshot_path": "/tmp/resolve_incident_final.png"
}
EOF

# 4. Save to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"