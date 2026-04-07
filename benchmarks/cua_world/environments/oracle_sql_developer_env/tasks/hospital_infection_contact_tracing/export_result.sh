#!/bin/bash
# Export script for Hospital Infection Contact Tracing Task
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png ga

# Sanitize output function
sanitize_int() { local val="$1" default="$2"; if [[ "$val" =~ ^[0-9]+$ ]]; then echo "$val"; else echo "$default"; fi; }

# Initialize variables
INDEX_VW_EXISTS="false"
INDEX_ROWS=0
EXPOSURES_VW_EXISTS="false"
EXPOSURES_ROWS=0
EXPOSED_SUBJECTS=""
HOTSPOT_MV_EXISTS="false"
ISOLATION_ORDERS_EXISTS="false"
ISOLATION_ORDERS_ROWS=0
ISOLATED_SUBJECTS=""
PROC_EXISTS="false"

# 1. Check INDEX_INFECTIONS_VW
VW_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'EHR_ANALYST' AND view_name = 'INDEX_INFECTIONS_VW';" "system" | tr -d '[:space:]')
if [ "${VW_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    INDEX_VW_EXISTS="true"
    INDEX_ROWS=$(oracle_query_raw "SELECT COUNT(*) FROM ehr_analyst.index_infections_vw;" "system" | tr -d '[:space:]')
    INDEX_ROWS=$(sanitize_int "$INDEX_ROWS" "0")
fi

# 2. Check PATIENT_EXPOSURES_VW
EXP_VW_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'EHR_ANALYST' AND view_name = 'PATIENT_EXPOSURES_VW';" "system" | tr -d '[:space:]')
if [ "${EXP_VW_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    EXPOSURES_VW_EXISTS="true"
    EXPOSURES_ROWS=$(oracle_query_raw "SELECT COUNT(*) FROM ehr_analyst.patient_exposures_vw;" "system" | tr -d '[:space:]')
    EXPOSURES_ROWS=$(sanitize_int "$EXPOSURES_ROWS" "0")
    
    # Get the subjects that were flagged as exposed
    EXPOSED_SUBJECTS=$(oracle_query_raw "SELECT LISTAGG(exposed_subject_id, ',') WITHIN GROUP (ORDER BY exposed_subject_id) FROM ehr_analyst.patient_exposures_vw;" "system" | tr -d '[:space:]')
fi

# 3. Check WARD_HOTSPOT_MV
MV_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_mviews WHERE owner = 'EHR_ANALYST' AND mview_name = 'WARD_HOTSPOT_MV';" "system" | tr -d '[:space:]')
if [ "${MV_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    HOTSPOT_MV_EXISTS="true"
fi

# 4. Check ISOLATION_ORDERS table and contents
ISO_TBL_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_tables WHERE owner = 'EHR_ANALYST' AND table_name = 'ISOLATION_ORDERS';" "system" | tr -d '[:space:]')
if [ "${ISO_TBL_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    ISOLATION_ORDERS_EXISTS="true"
    ISOLATION_ORDERS_ROWS=$(oracle_query_raw "SELECT COUNT(*) FROM ehr_analyst.isolation_orders;" "system" | tr -d '[:space:]')
    ISOLATION_ORDERS_ROWS=$(sanitize_int "$ISOLATION_ORDERS_ROWS" "0")
    
    # Get the subjects that were isolated
    ISOLATED_SUBJECTS=$(oracle_query_raw "SELECT LISTAGG(subject_id, ',') WITHIN GROUP (ORDER BY subject_id) FROM ehr_analyst.isolation_orders;" "system" | tr -d '[:space:]')
fi

# 5. Check PROC_FLAG_ISOLATION
PROC_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_procedures WHERE owner = 'EHR_ANALYST' AND object_name = 'PROC_FLAG_ISOLATION';" "system" | tr -d '[:space:]')
if [ "${PROC_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    PROC_EXISTS="true"
fi

# 6. Gather GUI evidence
GUI_EVIDENCE=$(collect_gui_evidence)

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "index_vw_exists": $INDEX_VW_EXISTS,
    "index_rows": $INDEX_ROWS,
    "exposures_vw_exists": $EXPOSURES_VW_EXISTS,
    "exposures_rows": $EXPOSURES_ROWS,
    "exposed_subjects": "$EXPOSED_SUBJECTS",
    "hotspot_mv_exists": $HOTSPOT_MV_EXISTS,
    "isolation_orders_exists": $ISOLATION_ORDERS_EXISTS,
    "isolation_orders_rows": $ISOLATION_ORDERS_ROWS,
    "isolated_subjects": "$ISOLATED_SUBJECTS",
    "proc_exists": $PROC_EXISTS,
    "screenshot_path": "/tmp/task_final.png",
    $GUI_EVIDENCE
}
EOF

# Move to final location safely
rm -f /tmp/infection_tracing_result.json 2>/dev/null || sudo rm -f /tmp/infection_tracing_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/infection_tracing_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/infection_tracing_result.json
chmod 666 /tmp/infection_tracing_result.json 2>/dev/null || sudo chmod 666 /tmp/infection_tracing_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/infection_tracing_result.json"
cat /tmp/infection_tracing_result.json
echo "=== Export complete ==="