#!/bin/bash
echo "=== Exporting consolidate_duplicate_patients result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# ------------------------------------------------------------------
# QUERY COUCHDB FOR RESULT
# ------------------------------------------------------------------

# Check Master Record
echo "Checking Master Record (P00801)..."
MASTER_DOC=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/patient_p1_P00801")
# Check if it exists (not found returns error or missing fields)
MASTER_EXISTS=$(echo "$MASTER_DOC" | grep -q '"_id":"patient_p1_P00801"' && echo "true" || echo "false")

# Extract fields from Master
if [ "$MASTER_EXISTS" == "true" ]; then
    # We need to handle that data might be nested in "data" property or top level
    # Using python to parse robustly
    MASTER_PHONE=$(echo "$MASTER_DOC" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    data = d.get('data', d)
    print(data.get('phone', ''))
except:
    print('')
")
    MASTER_ADDRESS=$(echo "$MASTER_DOC" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    data = d.get('data', d)
    print(data.get('address', ''))
except:
    print('')
")
else
    MASTER_PHONE=""
    MASTER_ADDRESS=""
fi

# Check Duplicate Record
echo "Checking Duplicate Record (P00802)..."
DUP_DOC=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/patient_p1_P00802")
# CouchDB returns {"error":"not_found","reason":"deleted"} or similar for deleted/missing docs
# Or it might have _deleted: true if we fetch with revisions, but direct GET on deleted doc usually 404s
DUP_HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/patient_p1_P00802")

if [ "$DUP_HTTP_CODE" == "404" ]; then
    DUP_DELETED="true"
else
    # Check for explicit _deleted flag if it returns 200 (unlikely for direct GET unless querying all_docs)
    DUP_DELETED=$(echo "$DUP_DOC" | grep -q '"_deleted":true' && echo "true" || echo "false")
fi

# ------------------------------------------------------------------
# CREATE RESULT JSON
# ------------------------------------------------------------------

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "master_exists": $MASTER_EXISTS,
    "master_phone": "$MASTER_PHONE",
    "master_address": "$MASTER_ADDRESS",
    "duplicate_deleted": $DUP_DELETED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="