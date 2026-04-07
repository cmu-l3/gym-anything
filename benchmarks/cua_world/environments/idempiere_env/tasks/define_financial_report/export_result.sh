#!/bin/bash
echo "=== Exporting Financial Report Definition Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query variables
CLIENT_ID=$(get_gardenworld_client_id)
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# --- Helper function for JSON escaping ---
json_escape() {
    echo "$1" | sed 's/"/\\"/g' | tr -d '\n'
}

# 1. Check Report Header
echo "Checking PA_Report..."
REPORT_JSON="{}"
REPORT_DATA=$(idempiere_query "SELECT pa_report_id, pa_reportlineset_id, pa_reportcolumnset_id, created FROM pa_report WHERE name='GP Board Report' AND ad_client_id=$CLIENT_ID ORDER BY created DESC LIMIT 1" 2>/dev/null)

if [ -n "$REPORT_DATA" ]; then
    IFS='|' read -r RPT_ID LINE_SET_ID COL_SET_ID RPT_CREATED <<< "$REPORT_DATA"
    REPORT_JSON="{\"exists\": true, \"id\": \"$RPT_ID\", \"line_set_id\": \"$LINE_SET_ID\", \"col_set_id\": \"$COL_SET_ID\", \"created\": \"$RPT_CREATED\"}"
else
    REPORT_JSON="{\"exists\": false}"
fi

# 2. Check Line Set
echo "Checking PA_ReportLineSet..."
LINESET_JSON="{}"
LINESET_DATA=$(idempiere_query "SELECT pa_reportlineset_id FROM pa_reportlineset WHERE name='Gross Profit Analysis' AND ad_client_id=$CLIENT_ID ORDER BY created DESC LIMIT 1" 2>/dev/null)

LINES_ARRAY="[]"
if [ -n "$LINESET_DATA" ]; then
    LINESET_ID="$LINESET_DATA"
    
    # Get lines detail
    # Format: ID|Name|Type|Oper1|Oper2
    LINES_QUERY="SELECT pa_reportline_id, name, linetype, oper_1_id, oper_2_id FROM pa_reportline WHERE pa_reportlineset_id=$LINESET_ID ORDER BY seqno"
    LINES_RAW=$(idempiere_query "$LINES_QUERY" 2>/dev/null)
    
    # Build JSON array of lines manually
    if [ -n "$LINES_RAW" ]; then
        LINES_ARRAY="["
        FIRST=true
        while IFS='|' read -r L_ID L_NAME L_TYPE L_OP1 L_OP2; do
            if [ "$FIRST" = true ]; then FIRST=false; else LINES_ARRAY+=","; fi
            LINES_ARRAY+="{\"id\": \"$L_ID\", \"name\": \"$(json_escape "$L_NAME")\", \"type\": \"$L_TYPE\", \"op1\": \"$L_OP1\", \"op2\": \"$L_OP2\"}"
        done <<< "$LINES_RAW"
        LINES_ARRAY+="]"
    fi
    LINESET_JSON="{\"exists\": true, \"id\": \"$LINESET_ID\", \"lines\": $LINES_ARRAY}"
else
    LINESET_JSON="{\"exists\": false}"
fi

# 3. Check Column Set
echo "Checking PA_ReportColumnSet..."
COLSET_JSON="{}"
COLSET_DATA=$(idempiere_query "SELECT pa_reportcolumnset_id FROM pa_reportcolumnset WHERE name='Current Period Analysis' AND ad_client_id=$CLIENT_ID ORDER BY created DESC LIMIT 1" 2>/dev/null)

COLS_ARRAY="[]"
if [ -n "$COLSET_DATA" ]; then
    COLSET_ID="$COLSET_DATA"
    
    # Get columns detail
    # Format: ID|Name|AmountType
    COLS_QUERY="SELECT pa_reportcolumn_id, name, amounttype FROM pa_reportcolumn WHERE pa_reportcolumnset_id=$COLSET_ID"
    COLS_RAW=$(idempiere_query "$COLS_QUERY" 2>/dev/null)
    
    if [ -n "$COLS_RAW" ]; then
        COLS_ARRAY="["
        FIRST=true
        while IFS='|' read -r C_ID C_NAME C_TYPE; do
            if [ "$FIRST" = true ]; then FIRST=false; else COLS_ARRAY+=","; fi
            COLS_ARRAY+="{\"id\": \"$C_ID\", \"name\": \"$(json_escape "$C_NAME")\", \"type\": \"$C_TYPE\"}"
        done <<< "$COLS_RAW"
        COLS_ARRAY+="]"
    fi
    COLSET_JSON="{\"exists\": true, \"id\": \"$COLSET_ID\", \"columns\": $COLS_ARRAY}"
else
    COLSET_JSON="{\"exists\": false}"
fi

# 4. Construct Final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START_TIME,
    "timestamp": "$(date -Iseconds)",
    "report": $REPORT_JSON,
    "line_set": $LINESET_JSON,
    "column_set": $COLSET_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json