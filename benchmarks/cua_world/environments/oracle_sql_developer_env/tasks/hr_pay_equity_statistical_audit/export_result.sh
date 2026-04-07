#!/bin/bash
echo "=== Exporting HR Pay Equity Statistical Audit results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Initialize flags
ANOVA_VW_EXISTS=false
TTEST_VW_EXISTS=false
CHISQ_VW_EXISTS=false
FUNC_EXISTS=false
FUNC_VALID=false
FUNC_TEST_VAL=0

USES_ANOVA=false
USES_TTEST=false
USES_CHISQ=false
USES_REGR_SLOPE=false
USES_REGR_INTERCEPT=false

CSV_EXISTS=false
CSV_SIZE=0
CSV_HAS_HEADERS=false

# 1. Check Views Existence
ANOVA_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner='HR_ANALYST' AND view_name='DEPT_INCOME_ANOVA_VW';" "system" | tr -d '[:space:]')
if [ "${ANOVA_CHECK:-0}" -gt 0 ] 2>/dev/null; then ANOVA_VW_EXISTS=true; fi

TTEST_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner='HR_ANALYST' AND view_name='GENDER_PAY_TTEST_VW';" "system" | tr -d '[:space:]')
if [ "${TTEST_CHECK:-0}" -gt 0 ] 2>/dev/null; then TTEST_VW_EXISTS=true; fi

CHISQ_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner='HR_ANALYST' AND view_name='ATTRITION_PROMO_XCT_VW';" "system" | tr -d '[:space:]')
if [ "${CHISQ_CHECK:-0}" -gt 0 ] 2>/dev/null; then CHISQ_VW_EXISTS=true; fi

# 2. Check Function Existence and Validity
FUNC_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_objects WHERE owner='HR_ANALYST' AND object_name='FN_INCOME_MODEL' AND object_type='FUNCTION';" "system" | tr -d '[:space:]')
if [ "${FUNC_CHECK:-0}" -gt 0 ] 2>/dev/null; then FUNC_EXISTS=true; fi

FUNC_VALID_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_objects WHERE owner='HR_ANALYST' AND object_name='FN_INCOME_MODEL' AND object_type='FUNCTION' AND status='VALID';" "system" | tr -d '[:space:]')
if [ "${FUNC_VALID_CHECK:-0}" -gt 0 ] 2>/dev/null; then 
    FUNC_VALID=true
    # Test function execution
    TEST_VAL=$(oracle_query_raw "SELECT ROUND(NVL(hr_analyst.fn_income_model('Sales Executive', 5), 0), 2) FROM dual;" "system" 2>/dev/null | tr -d '[:space:]')
    if [[ "$TEST_VAL" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        FUNC_TEST_VAL=$TEST_VAL
    fi
fi

# 3. Check source text for required Oracle statistical functions
# Check ANOVA view
if [ "$ANOVA_VW_EXISTS" = true ]; then
    TEXT=$(oracle_query_raw "SELECT text FROM all_views WHERE owner='HR_ANALYST' AND view_name='DEPT_INCOME_ANOVA_VW';" "system" 2>/dev/null)
    if echo "$TEXT" | grep -qiE "STATS_ONE_WAY_ANOVA"; then USES_ANOVA=true; fi
fi

# Check T-Test view
if [ "$TTEST_VW_EXISTS" = true ]; then
    TEXT=$(oracle_query_raw "SELECT text FROM all_views WHERE owner='HR_ANALYST' AND view_name='GENDER_PAY_TTEST_VW';" "system" 2>/dev/null)
    if echo "$TEXT" | grep -qiE "STATS_T_TEST_INDEP"; then USES_TTEST=true; fi
fi

# Check Chi-Square view
if [ "$CHISQ_VW_EXISTS" = true ]; then
    TEXT=$(oracle_query_raw "SELECT text FROM all_views WHERE owner='HR_ANALYST' AND view_name='ATTRITION_PROMO_XCT_VW';" "system" 2>/dev/null)
    if echo "$TEXT" | grep -qiE "STATS_CROSSTAB"; then USES_CHISQ=true; fi
fi

# Check Function source
if [ "$FUNC_EXISTS" = true ]; then
    TEXT=$(oracle_query_raw "SELECT text FROM all_source WHERE owner='HR_ANALYST' AND name='FN_INCOME_MODEL' ORDER BY line;" "system" 2>/dev/null)
    if echo "$TEXT" | grep -qiE "REGR_SLOPE"; then USES_REGR_SLOPE=true; fi
    if echo "$TEXT" | grep -qiE "REGR_INTERCEPT"; then USES_REGR_INTERCEPT=true; fi
fi

# 4. Check CSV export
CSV_PATH="/home/ga/Documents/exports/gender_pay_audit.csv"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS=true
    CSV_SIZE=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
    # Simple check for headers
    if head -n 1 "$CSV_PATH" | grep -qiE "job_role|t_statistic|p_value|significant"; then
        CSV_HAS_HEADERS=true
    fi
fi

# 5. Collect GUI evidence
GUI_EVIDENCE=$(collect_gui_evidence)

# Export to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "anova_vw_exists": $ANOVA_VW_EXISTS,
    "ttest_vw_exists": $TTEST_VW_EXISTS,
    "chisq_vw_exists": $CHISQ_VW_EXISTS,
    "func_exists": $FUNC_EXISTS,
    "func_valid": $FUNC_VALID,
    "func_test_val": $FUNC_TEST_VAL,
    "uses_anova": $USES_ANOVA,
    "uses_ttest": $USES_TTEST,
    "uses_chisq": $USES_CHISQ,
    "uses_regr_slope": $USES_REGR_SLOPE,
    "uses_regr_intercept": $USES_REGR_INTERCEPT,
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    "csv_has_headers": $CSV_HAS_HEADERS,
    $GUI_EVIDENCE
}
EOF

rm -f /tmp/hr_audit_result.json 2>/dev/null || sudo rm -f /tmp/hr_audit_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/hr_audit_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/hr_audit_result.json
chmod 666 /tmp/hr_audit_result.json 2>/dev/null || sudo chmod 666 /tmp/hr_audit_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Exported results to /tmp/hr_audit_result.json"
cat /tmp/hr_audit_result.json
echo "=== Export complete ==="