#!/bin/bash
echo "=== Exporting customize_print_format results ==="

source /workspace/scripts/task_utils.sh

CLIENT_ID=$(get_gardenworld_client_id)
if [ -z "$CLIENT_ID" ]; then CLIENT_ID=11; fi

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Query Database for the new Print Format
echo "--- Querying Database ---"

# Check if Format exists
# We select ID, IsTableBased, and the Table Name associated with it
FORMAT_INFO=$(idempiere_query "
    SELECT f.AD_PrintFormat_ID, t.TableName 
    FROM AD_PrintFormat f
    JOIN AD_Table t ON f.AD_Table_ID = t.AD_Table_ID
    WHERE f.Name='Customer Proposal' AND f.AD_Client_ID=$CLIENT_ID
" 2>/dev/null)

FORMAT_FOUND="false"
FORMAT_ID=""
TABLE_NAME=""

if [ -n "$FORMAT_INFO" ]; then
    FORMAT_FOUND="true"
    FORMAT_ID=$(echo "$FORMAT_INFO" | cut -d'|' -f1)
    TABLE_NAME=$(echo "$FORMAT_INFO" | cut -d'|' -f2)
fi

# Check for "PROPOSAL" text item
PROPOSAL_TEXT_FOUND="false"
if [ "$FORMAT_FOUND" = "true" ]; then
    # Look for an item where Name or PrintName is 'PROPOSAL'
    TEXT_COUNT=$(idempiere_query "
        SELECT COUNT(*) FROM AD_PrintFormatItem 
        WHERE AD_PrintFormat_ID=$FORMAT_ID 
        AND (PrintName='PROPOSAL' OR Name='PROPOSAL')
        AND IsActive='Y'
    " 2>/dev/null || echo "0")
    
    if [ "$TEXT_COUNT" -gt "0" ]; then
        PROPOSAL_TEXT_FOUND="true"
    fi
fi

# Check if "Line" column is hidden
LINE_COLUMN_HIDDEN="false"
LINE_COLUMN_FOUND="false"
if [ "$FORMAT_FOUND" = "true" ]; then
    # Find the item that corresponds to the 'Line' column of C_Order_Line (or similar)
    # Usually identified by Name='Line' or SortNo
    # We look for an item named 'Line' or 'Line No' and check IsPrinted
    
    IS_PRINTED=$(idempiere_query "
        SELECT IsPrinted FROM AD_PrintFormatItem 
        WHERE AD_PrintFormat_ID=$FORMAT_ID 
        AND (Name='Line' OR Name='Line No' OR PrintName='Line' OR PrintName='Line No')
        LIMIT 1
    " 2>/dev/null)

    if [ -n "$IS_PRINTED" ]; then
        LINE_COLUMN_FOUND="true"
        if [ "$IS_PRINTED" = "N" ]; then
            LINE_COLUMN_HIDDEN="true"
        fi
    fi
fi

# 3. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "format_found": $FORMAT_FOUND,
    "format_id": "${FORMAT_ID:-0}",
    "table_name": "${TABLE_NAME:-none}",
    "proposal_text_found": $PROPOSAL_TEXT_FOUND,
    "line_column_found": $LINE_COLUMN_FOUND,
    "line_column_hidden": $LINE_COLUMN_HIDDEN,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json