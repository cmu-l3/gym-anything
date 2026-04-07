#!/bin/bash
# Export script for AML Transaction Pattern Analysis
echo "=== Exporting AML Transaction Pattern Analysis Result ==="

source /workspace/scripts/task_utils.sh

# Record end state
TASK_END=$(date +%s)
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Extract database state
STRUCTURING_ALERTS_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM all_tables WHERE owner='AML_INVESTIGATOR' AND table_name='STRUCTURING_ALERTS';" "system" | tr -d '[:space:]')
LAYERING_ALERTS_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM all_tables WHERE owner='AML_INVESTIGATOR' AND table_name='LAYERING_ALERTS';" "system" | tr -d '[:space:]')
SAR_REC_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM all_tables WHERE owner='AML_INVESTIGATOR' AND table_name='SAR_RECOMMENDATIONS';" "system" | tr -d '[:space:]')
FUND_FLOW_VW_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner='AML_INVESTIGATOR' AND view_name='FUND_FLOW_VW';" "system" | tr -d '[:space:]')
RISK_SCORE_VW_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner='AML_INVESTIGATOR' AND view_name='CUSTOMER_RISK_SCORE_VW';" "system" | tr -d '[:space:]')
PROC_EXISTS=$(oracle_query_raw "SELECT COUNT(*) FROM all_procedures WHERE owner='AML_INVESTIGATOR' AND object_name='PROC_GENERATE_SAR_RECOMMENDATIONS';" "system" | tr -d '[:space:]')

# Check data within tables if they exist
SMURF_FOUND=0
STRUCT_ROWS=0
if [ "${STRUCTURING_ALERTS_COUNT:-0}" -gt 0 ]; then
    STRUCT_ROWS=$(oracle_query_raw "SELECT COUNT(*) FROM aml_investigator.structuring_alerts;" "system" | tr -d '[:space:]')
    # Check if Account 1002 (Bob Jones) or 1005 (Charlie Brown) are flagged
    SMURF_FOUND=$(oracle_query_raw "SELECT COUNT(*) FROM aml_investigator.structuring_alerts WHERE account_id IN (1002, 1005);" "system" | tr -d '[:space:]')
fi

LAYER_ROWS=0
LAYER_FOUND=0
if [ "${LAYERING_ALERTS_COUNT:-0}" -gt 0 ]; then
    LAYER_ROWS=$(oracle_query_raw "SELECT COUNT(*) FROM aml_investigator.layering_alerts;" "system" | tr -d '[:space:]')
    # Check if Account 1003 is flagged
    LAYER_FOUND=$(oracle_query_raw "SELECT COUNT(*) FROM aml_investigator.layering_alerts WHERE account_id = 1003;" "system" | tr -d '[:space:]')
fi

SAR_ROWS=0
SAR_NARRATIVE_OK="false"
SAR_THRESHOLD_OK="false"
if [ "${SAR_REC_COUNT:-0}" -gt 0 ]; then
    SAR_ROWS=$(oracle_query_raw "SELECT COUNT(*) FROM aml_investigator.sar_recommendations;" "system" | tr -d '[:space:]')
    # Check if low risk customers got in (threshold failure)
    LOW_RISK_SAR=$(oracle_query_raw "SELECT COUNT(*) FROM aml_investigator.sar_recommendations WHERE risk_score < 60;" "system" | tr -d '[:space:]')
    if [ "${LOW_RISK_SAR:-1}" = "0" ] && [ "${SAR_ROWS:-0}" -gt 0 ]; then
        SAR_THRESHOLD_OK="true"
    fi
    
    # Check narrative text content length (proxy for LISTAGG usage and detail)
    NARRATIVE_LEN=$(oracle_query_raw "SELECT NVL(MAX(LENGTH(narrative)), 0) FROM aml_investigator.sar_recommendations;" "system" | tr -d '[:space:]')
    if [ "${NARRATIVE_LEN:-0}" -gt 15 ]; then
        SAR_NARRATIVE_OK="true"
    fi
fi

# Check for specific Oracle features in source text
MATCH_RECOGNIZE_USED="false"
CONNECT_BY_USED="false"
LISTAGG_USED="false"

ALL_SOURCE_DUMP=$(oracle_query_raw "
SELECT text FROM all_source WHERE owner='AML_INVESTIGATOR'
UNION ALL
SELECT text FROM all_views WHERE owner='AML_INVESTIGATOR';
" "system" 2>/dev/null)

if echo "$ALL_SOURCE_DUMP" | grep -qi "MATCH_RECOGNIZE"; then
    MATCH_RECOGNIZE_USED="true"
fi
if echo "$ALL_SOURCE_DUMP" | grep -qiE "CONNECT BY|WITH RECURSIVE"; then
    CONNECT_BY_USED="true"
fi
if echo "$ALL_SOURCE_DUMP" | grep -qi "LISTAGG"; then
    LISTAGG_USED="true"
fi

# 3. Check CSV Export
CSV_PATH="/home/ga/aml_investigation_report.csv"
CSV_EXISTS="false"
CSV_SIZE=0
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
fi

# 4. Collect GUI Evidence
GUI_EVIDENCE=$(collect_gui_evidence)

# 5. Build JSON Result
TEMP_JSON=$(mktemp /tmp/aml_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "structuring_alerts_exists": $([ "${STRUCTURING_ALERTS_COUNT:-0}" -gt 0 ] && echo "true" || echo "false"),
    "structuring_rows": ${STRUCT_ROWS:-0},
    "smurf_accounts_found": ${SMURF_FOUND:-0},
    "layering_alerts_exists": $([ "${LAYERING_ALERTS_COUNT:-0}" -gt 0 ] && echo "true" || echo "false"),
    "layering_rows": ${LAYER_ROWS:-0},
    "layering_accounts_found": ${LAYER_FOUND:-0},
    "fund_flow_vw_exists": $([ "${FUND_FLOW_VW_COUNT:-0}" -gt 0 ] && echo "true" || echo "false"),
    "risk_score_vw_exists": $([ "${RISK_SCORE_VW_COUNT:-0}" -gt 0 ] && echo "true" || echo "false"),
    "proc_generate_sar_exists": $([ "${PROC_EXISTS:-0}" -gt 0 ] && echo "true" || echo "false"),
    "sar_recommendations_exists": $([ "${SAR_REC_COUNT:-0}" -gt 0 ] && echo "true" || echo "false"),
    "sar_rows": ${SAR_ROWS:-0},
    "sar_threshold_enforced": ${SAR_THRESHOLD_OK},
    "sar_narrative_populated": ${SAR_NARRATIVE_OK},
    "match_recognize_used": ${MATCH_RECOGNIZE_USED},
    "connect_by_used": ${CONNECT_BY_USED},
    "listagg_used": ${LISTAGG_USED},
    "csv_exists": ${CSV_EXISTS},
    "csv_size_bytes": ${CSV_SIZE},
    ${GUI_EVIDENCE}
}
EOF

# Move to final location safely
rm -f /tmp/aml_result.json 2>/dev/null || sudo rm -f /tmp/aml_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/aml_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/aml_result.json
chmod 666 /tmp/aml_result.json 2>/dev/null || sudo chmod 666 /tmp/aml_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/aml_result.json"
cat /tmp/aml_result.json
echo "=== Export complete ==="