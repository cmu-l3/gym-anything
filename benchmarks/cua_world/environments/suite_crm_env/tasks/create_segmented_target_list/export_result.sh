#!/bin/bash
echo "=== Exporting create_segmented_target_list results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query the database for the newly created target list
LIST_DATA=$(suitecrm_db_query "SELECT id, date_entered FROM prospect_lists WHERE name='Seattle Regional Campaign' AND deleted=0 ORDER BY date_entered DESC LIMIT 1")

LIST_FOUND="false"
LIST_ID=""
SEATTLE_COUNT=0
NON_SEATTLE_COUNT=0

if [ -n "$LIST_DATA" ]; then
    LIST_FOUND="true"
    LIST_ID=$(echo "$LIST_DATA" | awk -F'\t' '{print $1}')
    
    # Check how many Seattle contacts were linked
    SEATTLE_COUNT=$(suitecrm_db_query "
        SELECT COUNT(*) 
        FROM prospect_lists_prospects plp 
        JOIN contacts c ON plp.related_id = c.id 
        WHERE plp.prospect_list_id = '${LIST_ID}' 
          AND plp.related_type = 'Contacts' 
          AND plp.deleted=0 
          AND c.deleted=0 
          AND c.primary_address_city = 'Seattle'
    " | tr -d '[:space:]')
    
    # Check for DATA LEAKAGE: How many non-Seattle contacts were linked
    NON_SEATTLE_COUNT=$(suitecrm_db_query "
        SELECT COUNT(*) 
        FROM prospect_lists_prospects plp 
        JOIN contacts c ON plp.related_id = c.id 
        WHERE plp.prospect_list_id = '${LIST_ID}' 
          AND plp.related_type = 'Contacts' 
          AND plp.deleted=0 
          AND c.deleted=0 
          AND c.primary_address_city != 'Seattle'
    " | tr -d '[:space:]')
fi

# Fallback values for integers to prevent JSON formatting errors
SEATTLE_COUNT=${SEATTLE_COUNT:-0}
NON_SEATTLE_COUNT=${NON_SEATTLE_COUNT:-0}

# Generate Results JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "list_found": $LIST_FOUND,
  "list_id": "$(json_escape "${LIST_ID:-}")",
  "seattle_contacts_linked": $SEATTLE_COUNT,
  "non_seattle_contacts_linked": $NON_SEATTLE_COUNT
}
EOF

# Save result safely
safe_write_result "/tmp/task_result.json" "$(cat $TEMP_JSON)"
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="