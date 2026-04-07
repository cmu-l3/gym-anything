#!/bin/bash
echo "=== Exporting customize_lead_module_layout results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/layout_customization_final.png

# Query database for layout changes
TABID=$(vtiger_db_query "SELECT tabid FROM vtiger_tab WHERE name='Leads' LIMIT 1" | tr -d '[:space:]')

NEW_BLOCK_ID=""
IND_BLOCK=""
REV_BLOCK=""
EMP_BLOCK=""
FAX_PRESENCE="2"

if [ -n "$TABID" ]; then
    # Check if the block was created
    NEW_BLOCK_ID=$(vtiger_db_query "SELECT blockid FROM vtiger_blocks WHERE tabid=$TABID AND blocklabel='Qualification Metrics' LIMIT 1" | tr -d '[:space:]')
    
    # Check field locations
    IND_BLOCK=$(vtiger_db_query "SELECT block FROM vtiger_field WHERE tabid=$TABID AND fieldname='industry' LIMIT 1" | tr -d '[:space:]')
    REV_BLOCK=$(vtiger_db_query "SELECT block FROM vtiger_field WHERE tabid=$TABID AND fieldname='annualrevenue' LIMIT 1" | tr -d '[:space:]')
    EMP_BLOCK=$(vtiger_db_query "SELECT block FROM vtiger_field WHERE tabid=$TABID AND fieldname='noofemployees' LIMIT 1" | tr -d '[:space:]')
    
    # Check fax visibility (presence = 1 means hidden in Vtiger)
    FAX_PRESENCE=$(vtiger_db_query "SELECT presence FROM vtiger_field WHERE tabid=$TABID AND fieldname='fax' LIMIT 1" | tr -d '[:space:]')
fi

# Write results
TEMP_JSON=$(mktemp /tmp/layout_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
  "tab_id": "$TABID",
  "new_block_id": "$NEW_BLOCK_ID",
  "industry_block": "$IND_BLOCK",
  "revenue_block": "$REV_BLOCK",
  "employees_block": "$EMP_BLOCK",
  "fax_presence": "$FAX_PRESENCE"
}
EOF

safe_write_result "/tmp/layout_customization_result.json" "$(cat $TEMP_JSON)"
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/layout_customization_result.json"
cat /tmp/layout_customization_result.json
echo "=== customize_lead_module_layout export complete ==="