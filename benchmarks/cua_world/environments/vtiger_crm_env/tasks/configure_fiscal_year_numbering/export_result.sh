#!/bin/bash
echo "=== Exporting configure_fiscal_year_numbering results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/fiscal_numbering_final.png

# Fetch configuration details for each module from vtiger_modentity_num
Q_PREFIX=$(vtiger_db_query "SELECT prefix FROM vtiger_modentity_num WHERE semodule='Quotes'" | tr -d '\n' | awk '{$1=$1;print}')
Q_ID=$(vtiger_db_query "SELECT cur_id FROM vtiger_modentity_num WHERE semodule='Quotes'" | tr -d '[:space:]')

I_PREFIX=$(vtiger_db_query "SELECT prefix FROM vtiger_modentity_num WHERE semodule='Invoice'" | tr -d '\n' | awk '{$1=$1;print}')
I_ID=$(vtiger_db_query "SELECT cur_id FROM vtiger_modentity_num WHERE semodule='Invoice'" | tr -d '[:space:]')

P_PREFIX=$(vtiger_db_query "SELECT prefix FROM vtiger_modentity_num WHERE semodule='PurchaseOrder'" | tr -d '\n' | awk '{$1=$1;print}')
P_ID=$(vtiger_db_query "SELECT cur_id FROM vtiger_modentity_num WHERE semodule='PurchaseOrder'" | tr -d '[:space:]')

# Fetch the test quote the agent was supposed to create
QUOTE_DATA=$(vtiger_db_query "SELECT q.quoteid, q.quote_no, c.createdtime FROM vtiger_quotes q JOIN vtiger_crmentity c ON q.quoteid=c.crmid WHERE q.subject='FY2026 Numbering Test' LIMIT 1")

QUOTE_FOUND="false"
QUOTE_NO=""
QUOTE_TS=0

if [ -n "$QUOTE_DATA" ]; then
    QUOTE_FOUND="true"
    QUOTE_ID=$(echo "$QUOTE_DATA" | awk -F'\t' '{print $1}')
    QUOTE_NO=$(echo "$QUOTE_DATA" | awk -F'\t' '{print $2}')
    QUOTE_CREATED=$(echo "$QUOTE_DATA" | awk -F'\t' '{print $3}')
    # Convert createdtime to epoch for anti-gaming verification
    QUOTE_TS=$(date -d "$QUOTE_CREATED" +%s 2>/dev/null || echo "0")
fi

# Create result JSON
RESULT_JSON=$(cat << JSONEOF
{
  "quotes_prefix": "$(json_escape "$Q_PREFIX")",
  "quotes_cur_id": ${Q_ID:-0},
  "invoice_prefix": "$(json_escape "$I_PREFIX")",
  "invoice_cur_id": ${I_ID:-0},
  "po_prefix": "$(json_escape "$P_PREFIX")",
  "po_cur_id": ${P_ID:-0},
  "quote_found": ${QUOTE_FOUND},
  "quote_no": "$(json_escape "$QUOTE_NO")",
  "quote_timestamp": ${QUOTE_TS},
  "task_start_time": $(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
}
JSONEOF
)

safe_write_result "/tmp/fiscal_numbering_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/fiscal_numbering_result.json"
cat /tmp/fiscal_numbering_result.json
echo "=== configure_fiscal_year_numbering export complete ==="