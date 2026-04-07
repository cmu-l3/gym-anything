#!/bin/bash
set -e
echo "=== Exporting task results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot for VLM / evidence
take_screenshot /tmp/task_final_state.png

# Retrieve recorded variables
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
ACCOUNTS_TABID=$(cat /tmp/accounts_tabid.txt 2>/dev/null || echo "6")
INITIAL_FIELD_COUNT=$(cat /tmp/initial_field_count.txt 2>/dev/null || echo "0")

# Fetch current field count
CURRENT_FIELD_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_field WHERE tabid=${ACCOUNTS_TABID}" | tr -d '[:space:]')

# Fetch custom field properties if it was created
FIELD_DATA=$(vtiger_db_query "SELECT fieldname, uitype, block FROM vtiger_field WHERE fieldlabel='Customer Tier' AND tabid=${ACCOUNTS_TABID} LIMIT 1")

FIELD_EXISTS="false"
FIELD_NAME=""
FIELD_UITYPE=""
FIELD_BLOCK=""
if [ -n "$FIELD_DATA" ]; then
    FIELD_EXISTS="true"
    FIELD_NAME=$(echo "$FIELD_DATA" | awk -F'\t' '{print $1}')
    FIELD_UITYPE=$(echo "$FIELD_DATA" | awk -F'\t' '{print $2}')
    FIELD_BLOCK=$(echo "$FIELD_DATA" | awk -F'\t' '{print $3}')
fi

# Fetch picklist values if field exists
PICKLIST_VALUES=""
if [ "$FIELD_EXISTS" = "true" ] && [ -n "$FIELD_NAME" ]; then
    # In Vtiger, picklist values are typically stored in a table named after the field
    TABLE_EXISTS=$(vtiger_db_query "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='vtiger' AND table_name='vtiger_${FIELD_NAME}'" | tr -d '[:space:]')
    
    if [ "$TABLE_EXISTS" -gt 0 ]; then
        # Commas separated values list
        PICKLIST_VALUES=$(vtiger_db_query "SELECT ${FIELD_NAME} FROM vtiger_${FIELD_NAME}" | tr '\n' ',' | sed 's/,$//')
    else
        # Try checking vtiger_role2picklist in case it's role-based
        PICKLIST_ID=$(vtiger_db_query "SELECT picklistid FROM vtiger_picklist WHERE name='${FIELD_NAME}' LIMIT 1" | tr -d '[:space:]')
        if [ -n "$PICKLIST_ID" ]; then
             PICKLIST_VALUES=$(vtiger_db_query "SELECT p.${FIELD_NAME} FROM vtiger_role2picklist rp INNER JOIN vtiger_${FIELD_NAME} p ON rp.picklistvalueid=p.picklist_valueid" | tr '\n' ',' | sed 's/,$//')
        fi
    fi
fi

# Get the intended block ID for Organization Information
ORG_INFO_BLOCKID=$(vtiger_db_query "SELECT blockid FROM vtiger_blocks WHERE tabid=${ACCOUNTS_TABID} AND blocklabel='LBL_ACCOUNT_INFORMATION' LIMIT 1" | tr -d '[:space:]')

# Prepare JSON
RESULT_JSON=$(cat << EOF
{
    "task_start_time": $TASK_START,
    "accounts_tabid": "$ACCOUNTS_TABID",
    "initial_field_count": $INITIAL_FIELD_COUNT,
    "current_field_count": $CURRENT_FIELD_COUNT,
    "field_exists": $FIELD_EXISTS,
    "field_name": "$(json_escape "$FIELD_NAME")",
    "field_uitype": "$(json_escape "$FIELD_UITYPE")",
    "field_block": "$(json_escape "$FIELD_BLOCK")",
    "target_block_id": "$(json_escape "$ORG_INFO_BLOCKID")",
    "picklist_values": "$(json_escape "$PICKLIST_VALUES")"
}
EOF
)

# Safely write the results
safe_write_result "/tmp/task_result.json" "$RESULT_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="