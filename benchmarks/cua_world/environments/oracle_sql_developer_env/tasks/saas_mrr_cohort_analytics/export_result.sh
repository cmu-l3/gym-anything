#!/bin/bash
echo "=== Exporting SaaS MRR Analytics Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Initialize output variables
PROMO_VW_EXISTS="false"
MATCH_RECOGNIZE_USED="false"
ABUSER_IDS=""

COHORT_VW_EXISTS="false"
PIVOT_USED="false"
COHORT_M3_VALUE="0"
COHORT_HAS_M_COLS="false"

WATERFALL_EXISTS="false"
WATERFALL_ROWS="0"
WATERFALL_MATH_VALID="0"
WATERFALL_JUNE_CHURN="0"
WATERFALL_HAS_COLS="false"

# 1. Check PROMO_ABUSERS_VW
VW_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'SAAS_ADMIN' AND view_name = 'PROMO_ABUSERS_VW';" "system" | tr -d '[:space:]')
if [ "${VW_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    PROMO_VW_EXISTS="true"
    
    # Check for MATCH_RECOGNIZE
    VW_DDL=$(oracle_query_raw "SELECT DBMS_METADATA.GET_DDL('VIEW', 'PROMO_ABUSERS_VW', 'SAAS_ADMIN') FROM DUAL;" "system" 2>/dev/null)
    if echo "$VW_DDL" | grep -qiE "MATCH_RECOGNIZE"; then
        MATCH_RECOGNIZE_USED="true"
    fi
    
    # Extract Abusers found
    ABUSER_IDS=$(oracle_query_raw "SELECT LISTAGG(customer_id, ',') WITHIN GROUP (ORDER BY customer_id) FROM saas_admin.promo_abusers_vw;" "system" 2>/dev/null)
fi

# 2. Check COHORT_RETENTION_VW
VW_CHECK2=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'SAAS_ADMIN' AND view_name = 'COHORT_RETENTION_VW';" "system" | tr -d '[:space:]')
if [ "${VW_CHECK2:-0}" -gt 0 ] 2>/dev/null; then
    COHORT_VW_EXISTS="true"
    
    # Check for PIVOT
    VW_DDL2=$(oracle_query_raw "SELECT DBMS_METADATA.GET_DDL('VIEW', 'COHORT_RETENTION_VW', 'SAAS_ADMIN') FROM DUAL;" "system" 2>/dev/null)
    if echo "$VW_DDL2" | grep -qiE "\bPIVOT\b"; then
        PIVOT_USED="true"
    fi
    
    # Check if M columns exist
    COL_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_tab_cols WHERE owner='SAAS_ADMIN' AND table_name='COHORT_RETENTION_VW' AND column_name IN ('M0','M1','M2','M3','M4','M5','M6');" "system" | tr -d '[:space:]')
    if [ "${COL_CHECK:-0}" -eq 7 ] 2>/dev/null; then
        COHORT_HAS_M_COLS="true"
    fi
    
    # Extract M3 for Jan 2023 Cohort (just a sanity check value)
    COHORT_M3_VALUE=$(oracle_query_raw "SELECT NVL(MAX(M3), 0) FROM saas_admin.cohort_retention_vw WHERE TO_CHAR(cohort_month, 'YYYY-MM') = '2023-01';" "system" | tr -d '[:space:]')
fi

# 3. Check MRR_WATERFALL_2023
TBL_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_tables WHERE owner = 'SAAS_ADMIN' AND table_name = 'MRR_WATERFALL_2023';" "system" | tr -d '[:space:]')
if [ "${TBL_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    WATERFALL_EXISTS="true"
    
    # Check total rows
    WATERFALL_ROWS=$(oracle_query_raw "SELECT COUNT(*) FROM saas_admin.mrr_waterfall_2023;" "system" | tr -d '[:space:]')
    
    # Check columns
    COL_CHECK2=$(oracle_query_raw "SELECT COUNT(*) FROM all_tab_cols WHERE owner='SAAS_ADMIN' AND table_name='MRR_WATERFALL_2023' AND column_name IN ('REPORTING_MONTH', 'BEGINNING_MRR', 'NEW_MRR', 'EXPANSION_MRR', 'CONTRACTION_MRR', 'CHURN_MRR', 'REACTIVATION_MRR', 'ENDING_MRR');" "system" | tr -d '[:space:]')
    if [ "${COL_CHECK2:-0}" -eq 8 ] 2>/dev/null; then
        WATERFALL_HAS_COLS="true"
        
        # Check math integrity (how many rows have correct math)
        WATERFALL_MATH_VALID=$(oracle_query_raw "
        SELECT COUNT(*) FROM saas_admin.mrr_waterfall_2023 
        WHERE ROUND(NVL(BEGINNING_MRR,0) + NVL(NEW_MRR,0) + NVL(EXPANSION_MRR,0) - NVL(CONTRACTION_MRR,0) - NVL(CHURN_MRR,0) + NVL(REACTIVATION_MRR,0), 2) = ROUND(NVL(ENDING_MRR,0), 2);" "system" | tr -d '[:space:]')
        
        # Check June Churn (Should be 250 based on seed data)
        WATERFALL_JUNE_CHURN=$(oracle_query_raw "SELECT NVL(SUM(CHURN_MRR), 0) FROM saas_admin.mrr_waterfall_2023 WHERE TO_CHAR(REPORTING_MONTH, 'YYYY-MM') = '2023-06';" "system" | tr -d '[:space:]')
    fi
fi

# 4. Collect GUI Evidence
GUI_EVIDENCE=$(collect_gui_evidence)

# 5. Build JSON Export
TEMP_JSON=$(mktemp /tmp/saas_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "promo_vw_exists": $PROMO_VW_EXISTS,
    "match_recognize_used": $MATCH_RECOGNIZE_USED,
    "abuser_ids": "$ABUSER_IDS",
    "cohort_vw_exists": $COHORT_VW_EXISTS,
    "pivot_used": $PIVOT_USED,
    "cohort_has_m_cols": $COHORT_HAS_M_COLS,
    "cohort_m3_value": "$COHORT_M3_VALUE",
    "waterfall_exists": $WATERFALL_EXISTS,
    "waterfall_rows": ${WATERFALL_ROWS:-0},
    "waterfall_has_cols": $WATERFALL_HAS_COLS,
    "waterfall_math_valid_rows": ${WATERFALL_MATH_VALID:-0},
    "waterfall_june_churn": ${WATERFALL_JUNE_CHURN:-0},
    $GUI_EVIDENCE
}
EOF

# Move securely
rm -f /tmp/saas_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/saas_result.json
chmod 666 /tmp/saas_result.json
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/saas_result.json"
cat /tmp/saas_result.json
echo "=== Export Complete ==="