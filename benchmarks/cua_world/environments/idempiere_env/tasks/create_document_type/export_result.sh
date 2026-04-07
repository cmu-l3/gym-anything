#!/bin/bash
echo "=== Exporting create_document_type results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CLIENT_ID=$(get_gardenworld_client_id)

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Query the Sequence
# We look for the specific name created during the task timeframe
echo "--- Querying Sequence ---"
SEQ_JSON=$(idempiere_query "
    SELECT row_to_json(t) FROM (
        SELECT ad_sequence_id, name, currentnext, incrementno, isactive, created
        FROM ad_sequence 
        WHERE name = 'Web_Sales_Seq_2025' 
        AND ad_client_id = $CLIENT_ID
        AND isactive = 'Y'
        ORDER BY created DESC LIMIT 1
    ) t
" 2>/dev/null || echo "{}")

if [ -z "$SEQ_JSON" ]; then SEQ_JSON="{}"; fi

# 3. Query the Document Type
# We join with AD_Sequence to get the sequence name linked to the doc type
echo "--- Querying Document Type ---"
DOCTYPE_JSON=$(idempiere_query "
    SELECT row_to_json(t) FROM (
        SELECT dt.c_doctype_id, dt.name, dt.docbasetype, dt.docsubtypeso, 
               dt.ad_sequence_id, s.name as sequence_name, dt.isactive, dt.created
        FROM c_doctype dt
        LEFT JOIN ad_sequence s ON dt.ad_sequence_id = s.ad_sequence_id
        WHERE dt.name = 'Web Standard Order' 
        AND dt.ad_client_id = $CLIENT_ID
        AND dt.isactive = 'Y'
        ORDER BY dt.created DESC LIMIT 1
    ) t
" 2>/dev/null || echo "{}")

if [ -z "$DOCTYPE_JSON" ]; then DOCTYPE_JSON="{}"; fi

# 4. Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "sequence": $SEQ_JSON,
    "doctype": $DOCTYPE_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="