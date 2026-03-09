#!/bin/bash
# Export results for Financial Compliance Audit Investigation task
echo "=== Exporting Financial Audit results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Initialize all flags
TRIGGER_EXISTS=false
TRIGGER_ENABLED=false
TRIGGER_ON_EMPLOYEES=false
LOG_TABLE_EXISTS=false
LOG_TABLE_HAS_SALARY_COLS=false
AUDIT_CSV_EXISTS=false
AUDIT_CSV_SIZE=0
CSV_HAS_SALARY_DATA=false
CSV_HAS_EXPENSE_DATA=false
EXPENSE_TABLE_EXISTS=false

# --- Check SALARY_AUDIT_TRG trigger ---
TRIGGER_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_triggers WHERE owner = 'HR' AND trigger_name = 'SALARY_AUDIT_TRG';" "system" | tr -d '[:space:]')
if [ "${TRIGGER_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    TRIGGER_EXISTS=true

    # Check trigger is enabled
    TRIGGER_STATUS=$(oracle_query_raw "SELECT status FROM all_triggers WHERE owner = 'HR' AND trigger_name = 'SALARY_AUDIT_TRG';" "system" | tr -d '[:space:]')
    if [ "$TRIGGER_STATUS" = "ENABLED" ]; then
        TRIGGER_ENABLED=true
    fi

    # Check it fires on EMPLOYEES table
    TRIGGER_TABLE=$(oracle_query_raw "SELECT table_name FROM all_triggers WHERE owner = 'HR' AND trigger_name = 'SALARY_AUDIT_TRG';" "system" | tr -d '[:space:]')
    if [ "$TRIGGER_TABLE" = "EMPLOYEES" ]; then
        TRIGGER_ON_EMPLOYEES=true
    fi
fi

# Also look for any trigger on EMPLOYEES that logs to SALARY_CHANGE_LOG (flexible name check)
ANY_SALARY_TRIGGER=$(oracle_query_raw "SELECT COUNT(*) FROM all_triggers WHERE owner = 'HR' AND table_name = 'EMPLOYEES' AND status = 'ENABLED';" "system" | tr -d '[:space:]')
ANY_SALARY_TRIGGER=${ANY_SALARY_TRIGGER:-0}

# --- Check SALARY_CHANGE_LOG table structure ---
LOG_TABLE_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_tables WHERE owner = 'HR' AND table_name = 'SALARY_CHANGE_LOG';" "system" | tr -d '[:space:]')
if [ "${LOG_TABLE_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    LOG_TABLE_EXISTS=true

    # Check for salary-related columns (old_salary or new_salary or both)
    SALARY_COL_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM all_tab_columns WHERE owner = 'HR' AND table_name = 'SALARY_CHANGE_LOG' AND column_name IN ('OLD_SALARY','NEW_SALARY','SALARY','OLD_SAL','NEW_SAL');" "system" | tr -d '[:space:]')
    if [ "${SALARY_COL_COUNT:-0}" -ge 1 ] 2>/dev/null; then
        LOG_TABLE_HAS_SALARY_COLS=true
    fi

    # Count actual log entries (populated by trigger when salary changes occur)
    LOG_ENTRY_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM hr.salary_change_log;" "system" | tr -d '[:space:]')
    LOG_ENTRY_COUNT=${LOG_ENTRY_COUNT:-0}
fi

# --- Check audit CSV file ---
AUDIT_CSV_PATH="/home/ga/Documents/exports/audit_findings.csv"
if [ -f "$AUDIT_CSV_PATH" ]; then
    AUDIT_CSV_EXISTS=true
    AUDIT_CSV_SIZE=$(wc -c < "$AUDIT_CSV_PATH" 2>/dev/null)
    AUDIT_CSV_SIZE=${AUDIT_CSV_SIZE:-0}

    # Check for salary violation keywords (case insensitive)
    if grep -qiE "salary|violation|range|min|max|101|200|114|139|Kochhar|Whalen|Raphaely|Seo" "$AUDIT_CSV_PATH" 2>/dev/null; then
        CSV_HAS_SALARY_DATA=true
    fi

    # Check for expense duplicate keywords
    if grep -qiE "duplicate|expense|repeated|100|103|1250|420" "$AUDIT_CSV_PATH" 2>/dev/null; then
        CSV_HAS_EXPENSE_DATA=true
    fi
fi

# --- Check EXPENSE_REPORTS table still exists ---
EXP_TABLE_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_tables WHERE owner = 'HR' AND table_name = 'EXPENSE_REPORTS';" "system" | tr -d '[:space:]')
if [ "${EXP_TABLE_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    EXPENSE_TABLE_EXISTS=true
fi

# --- Get baseline values ---
INITIAL_TRIGGER_COUNT=$(cat /tmp/initial_hr_trigger_count 2>/dev/null || echo "0")

# --- Collect GUI evidence ---
GUI_EVIDENCE=$(collect_gui_evidence 2>/dev/null || echo '"gui_evidence": {"sql_history_count": 0, "mru_connection_count": 0, "window_title": "", "window_title_changed": false, "sqldev_oracle_sessions": 0}')

# --- Write result JSON ---
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "trigger_exists": $TRIGGER_EXISTS,
    "trigger_enabled": $TRIGGER_ENABLED,
    "trigger_on_employees": $TRIGGER_ON_EMPLOYEES,
    "any_salary_trigger_count": ${ANY_SALARY_TRIGGER:-0},
    "log_table_exists": $LOG_TABLE_EXISTS,
    "log_table_has_salary_cols": $LOG_TABLE_HAS_SALARY_COLS,
    "log_entry_count": ${LOG_ENTRY_COUNT:-0},
    "audit_csv_exists": $AUDIT_CSV_EXISTS,
    "audit_csv_size": ${AUDIT_CSV_SIZE:-0},
    "csv_has_salary_data": $CSV_HAS_SALARY_DATA,
    "csv_has_expense_data": $CSV_HAS_EXPENSE_DATA,
    "expense_table_exists": $EXPENSE_TABLE_EXISTS,
    "initial_trigger_count": ${INITIAL_TRIGGER_COUNT:-0},
    $GUI_EVIDENCE,
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/financial_audit_result.json 2>/dev/null || sudo rm -f /tmp/financial_audit_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/financial_audit_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/financial_audit_result.json
chmod 666 /tmp/financial_audit_result.json 2>/dev/null || sudo chmod 666 /tmp/financial_audit_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/financial_audit_result.json"
cat /tmp/financial_audit_result.json
echo "=== Export complete ==="
