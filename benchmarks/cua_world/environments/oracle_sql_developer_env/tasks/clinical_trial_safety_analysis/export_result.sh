#!/bin/bash
echo "=== Exporting Clinical Trial Safety Analysis Result ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

take_screenshot /tmp/task_final.png

# Initialize tracking variables
DEVIATION_COUNT=0
DEVIATION_TYPES=0
TIME_TO_ONSET_EXISTS=false
TIME_VW_LOGIC_OK=false
SIGNAL_DETECTION_EXISTS=false
SIGNAL_VW_LOGIC_OK=false
LAB_SHIFT_EXISTS=false
LAB_VW_LOGIC_OK=false
SDTM_DM_EXISTS=false
SDTM_AE_EXISTS=false
SDTM_LB_EXISTS=false
SAFETY_MV_EXISTS=false
SAFETY_MV_PIVOT_USED=false
CSV_EXISTS=false
CSV_SIZE=0

# --- 1. Check Protocol Deviations ---
DEVIATION_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM trial_dm.protocol_deviations;" "system" | tr -d '[:space:]')
DEVIATION_COUNT=${DEVIATION_COUNT:-0}

DEVIATION_TYPES=$(oracle_query_raw "SELECT COUNT(DISTINCT deviation_type) FROM trial_dm.protocol_deviations;" "system" | tr -d '[:space:]')
DEVIATION_TYPES=${DEVIATION_TYPES:-0}

# --- 2. Check TIME_TO_ONSET_VW ---
VW_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'TRIAL_DM' AND view_name = 'TIME_TO_ONSET_VW';" "system" | tr -d '[:space:]')
if [ "${VW_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    TIME_TO_ONSET_EXISTS=true
    # Verify it actually returns rows with categorized risk windows
    RISK_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM trial_dm.time_to_onset_vw WHERE UPPER(risk_window) IN ('IMMEDIATE', 'EARLY', 'DELAYED', 'LATE');" "system" | tr -d '[:space:]')
    if [ "${RISK_CHECK:-0}" -gt 0 ] 2>/dev/null; then
        TIME_VW_LOGIC_OK=true
    fi
fi

# --- 3. Check SIGNAL_DETECTION_VW ---
VW_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'TRIAL_DM' AND view_name = 'SIGNAL_DETECTION_VW';" "system" | tr -d '[:space:]')
if [ "${VW_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    SIGNAL_DETECTION_EXISTS=true
    
    # Check if PRR calculation logic exists via source
    SRC=$(oracle_query_raw "SELECT DBMS_METADATA.GET_DDL('VIEW', 'SIGNAL_DETECTION_VW', 'TRIAL_DM') FROM DUAL;" "system" 2>/dev/null)
    if echo "$SRC" | grep -qiE "/|PRR"; then
        SIGNAL_VW_LOGIC_OK=true
    fi
fi

# --- 4. Check LAB_SHIFT_ANALYSIS_VW ---
VW_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'TRIAL_DM' AND view_name = 'LAB_SHIFT_ANALYSIS_VW';" "system" | tr -d '[:space:]')
if [ "${VW_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    LAB_SHIFT_EXISTS=true
    SRC=$(oracle_query_raw "SELECT DBMS_METADATA.GET_DDL('VIEW', 'LAB_SHIFT_ANALYSIS_VW', 'TRIAL_DM') FROM DUAL;" "system" 2>/dev/null)
    if echo "$SRC" | grep -qiE "FIRST_VALUE|LAG|OVER"; then
        LAB_VW_LOGIC_OK=true
    fi
fi

# --- 5. Check CDISC SDTM Views ---
DM_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'TRIAL_DM' AND view_name = 'SDTM_DM';" "system" | tr -d '[:space:]')
if [ "${DM_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    COLS=$(oracle_query_raw "SELECT COUNT(*) FROM all_tab_columns WHERE owner = 'TRIAL_DM' AND table_name = 'SDTM_DM' AND column_name IN ('STUDYID', 'USUBJID', 'ARM', 'RFSTDTC');" "system" | tr -d '[:space:]')
    if [ "${COLS:-0}" -ge 4 ] 2>/dev/null; then
        SDTM_DM_EXISTS=true
    fi
fi

AE_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'TRIAL_DM' AND view_name = 'SDTM_AE';" "system" | tr -d '[:space:]')
if [ "${AE_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    COLS=$(oracle_query_raw "SELECT COUNT(*) FROM all_tab_columns WHERE owner = 'TRIAL_DM' AND table_name = 'SDTM_AE' AND column_name IN ('USUBJID', 'AETERM', 'AEDECOD', 'AEBODSYS', 'AESTDTC');" "system" | tr -d '[:space:]')
    if [ "${COLS:-0}" -ge 5 ] 2>/dev/null; then
        SDTM_AE_EXISTS=true
    fi
fi

LB_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'TRIAL_DM' AND view_name = 'SDTM_LB';" "system" | tr -d '[:space:]')
if [ "${LB_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    COLS=$(oracle_query_raw "SELECT COUNT(*) FROM all_tab_columns WHERE owner = 'TRIAL_DM' AND table_name = 'SDTM_LB' AND column_name IN ('USUBJID', 'LBTESTCD', 'LBORRES', 'VISITNUM');" "system" | tr -d '[:space:]')
    if [ "${COLS:-0}" -ge 4 ] 2>/dev/null; then
        SDTM_LB_EXISTS=true
    fi
fi

# --- 6. Check SAFETY_SUMMARY_MV ---
MV_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_mviews WHERE owner = 'TRIAL_DM' AND mview_name = 'SAFETY_SUMMARY_MV';" "system" | tr -d '[:space:]')
if [ "${MV_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    SAFETY_MV_EXISTS=true
    SRC=$(oracle_query_raw "SELECT DBMS_METADATA.GET_DDL('MATERIALIZED_VIEW', 'SAFETY_SUMMARY_MV', 'TRIAL_DM') FROM DUAL;" "system" 2>/dev/null)
    if echo "$SRC" | grep -qi "PIVOT"; then
        SAFETY_MV_PIVOT_USED=true
    fi
fi

# --- 7. Check CSV Export ---
CSV_PATH="/home/ga/safety_summary_report.csv"
if [ -f "$CSV_PATH" ]; then
    CSV_SIZE=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$CSV_SIZE" -gt 50 ]; then
        CSV_EXISTS=true
    fi
fi

# --- GUI Evidence ---
GUI_JSON=$(collect_gui_evidence)

# --- Create JSON Result ---
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "deviation_count": $DEVIATION_COUNT,
    "deviation_types": $DEVIATION_TYPES,
    "time_to_onset_exists": $TIME_TO_ONSET_EXISTS,
    "time_vw_logic_ok": $TIME_VW_LOGIC_OK,
    "signal_detection_exists": $SIGNAL_DETECTION_EXISTS,
    "signal_vw_logic_ok": $SIGNAL_VW_LOGIC_OK,
    "lab_shift_exists": $LAB_SHIFT_EXISTS,
    "lab_vw_logic_ok": $LAB_VW_LOGIC_OK,
    "sdtm_dm_exists": $SDTM_DM_EXISTS,
    "sdtm_ae_exists": $SDTM_AE_EXISTS,
    "sdtm_lb_exists": $SDTM_LB_EXISTS,
    "safety_mv_exists": $SAFETY_MV_EXISTS,
    "safety_mv_pivot_used": $SAFETY_MV_PIVOT_USED,
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    ${GUI_JSON}
}
EOF

# Move to final location safely
rm -f /tmp/clinical_safety_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/clinical_safety_result.json
chmod 666 /tmp/clinical_safety_result.json
rm -f "$TEMP_JSON"

echo "Export complete."