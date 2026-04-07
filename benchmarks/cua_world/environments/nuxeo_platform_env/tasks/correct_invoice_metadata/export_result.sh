#!/bin/bash
echo "=== Exporting correct_invoice_metadata results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Fetch Ground Truth
GROUND_TRUTH_FILE="/var/lib/nuxeo/invoice_ground_truth.json"
if [ -f "$GROUND_TRUTH_FILE" ]; then
    GT_JSON=$(cat "$GROUND_TRUTH_FILE")
else
    GT_JSON="{}"
fi

# 2. Fetch Document State from Nuxeo API
DOC_UID=$(cat /tmp/task_doc_uid.txt 2>/dev/null || echo "")
DOC_JSON="{}"
DOC_EXISTS="false"
DOC_MODIFIED_AFTER_START="false"

if [ -n "$DOC_UID" ]; then
    API_RESPONSE=$(nuxeo_api GET "/id/$DOC_UID")
    HTTP_CODE=$(echo "$API_RESPONSE" | grep -o '"entity-type":"document"' >/dev/null && echo "200" || echo "404")

    if [ "$HTTP_CODE" = "200" ]; then
        DOC_EXISTS="true"
        DOC_JSON="$API_RESPONSE"
        
        # Check modification time
        LAST_MODIFIED_STR=$(echo "$API_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('lastModified',''))")
        # Nuxeo returns ISO8601, convert to timestamp
        if [ -n "$LAST_MODIFIED_STR" ]; then
            LAST_MOD_TS=$(date -d "$LAST_MODIFIED_STR" +%s 2>/dev/null || echo "0")
            # Get task start time from ground truth file if possible, else 0
            GT_START=$(echo "$GT_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('task_start_time', 0))")
            
            if [ "$LAST_MOD_TS" -gt "$GT_START" ]; then
                DOC_MODIFIED_AFTER_START="true"
            fi
        fi
    fi
fi

# 3. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 4. Construct Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" <<EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "doc_exists": $DOC_EXISTS,
    "doc_modified": $DOC_MODIFIED_AFTER_START,
    "ground_truth": $GT_JSON,
    "document_metadata": $DOC_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save to public location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="