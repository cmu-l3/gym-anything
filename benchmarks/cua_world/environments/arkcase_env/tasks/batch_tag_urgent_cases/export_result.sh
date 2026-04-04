#!/bin/bash
echo "=== Exporting Batch Tagging Result ==="

source /workspace/scripts/task_utils.sh

# Record task end info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
IDS_FILE="/home/ga/.hidden_case_ids"

# Take final screenshot
take_screenshot /tmp/task_final.png

echo "Checking case states via API..."

# Prepare result structure
RESULTS_ARRAY="[]"

if [ -f "$IDS_FILE" ]; then
    while IFS="|" read -r case_id priority title; do
        if [ -z "$case_id" ]; then continue; fi
        
        echo "Checking Case $case_id ($priority)..."
        
        # Fetch case details including tags
        # Note: API structure for tags can vary (sometimes list of strings, sometimes objects)
        # We fetch the full object
        API_RESP=$(curl -sk -X GET \
            -u "${ARKCASE_ADMIN}:${ARKCASE_PASS}" \
            -H "Accept: application/json" \
            "${ARKCASE_URL}/api/v1/plugin/complaint/${case_id}")
            
        # Parse tags using python to handle JSON complexity
        # Returns a JSON array of tag strings
        TAGS_JSON=$(echo "$API_RESP" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    tags = data.get('tags', [])
    # Normalize: tags might be strings or objects with 'name'
    tag_names = []
    for t in tags:
        if isinstance(t, dict):
            tag_names.append(t.get('name', ''))
        else:
            tag_names.append(str(t))
    print(json.dumps(tag_names))
except Exception as e:
    print('[]')
")
        
        # Check other fields for collateral damage
        CURRENT_STATUS=$(echo "$API_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status', ''))" 2>/dev/null)
        
        # Construct JSON object for this case
        CASE_OBJ="{\"id\": \"$case_id\", \"priority\": \"$priority\", \"title\": \"$title\", \"tags\": $TAGS_JSON, \"status\": \"$CURRENT_STATUS\"}"
        
        # Append to results array
        if [ "$RESULTS_ARRAY" == "[]" ]; then
            RESULTS_ARRAY="[$CASE_OBJ"
        else
            RESULTS_ARRAY="$RESULTS_ARRAY, $CASE_OBJ"
        fi
        
    done < "$IDS_FILE"
    
    if [ "$RESULTS_ARRAY" != "[]" ]; then
        RESULTS_ARRAY="$RESULTS_ARRAY]"
    fi
else
    echo "ERROR: IDs file not found!"
fi

# Create final JSON output
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "cases_analyzed": $RESULTS_ARRAY,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="