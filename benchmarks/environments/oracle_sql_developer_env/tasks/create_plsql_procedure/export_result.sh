#!/bin/bash
echo "=== Exporting Create PL/SQL Procedure results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Initialize
PROCEDURE_EXISTS=false
PROCEDURE_VALID=false
PROCEDURE_NEWLY_CREATED=false
PROCEDURE_HAS_OUT_PARAM=false
SALARIES_UPDATED=false
SALARY_INCREASE_CORRECT=false
SQL_DEVELOPER_RUNNING=false

# Check SQL Developer running
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "sql developer\|oracle sql"; then
    SQL_DEVELOPER_RUNNING=true
fi

# Check if procedure exists
PROC_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM user_procedures WHERE object_name = 'GIVE_DEPARTMENT_RAISE' AND object_type = 'PROCEDURE';" "hr" | tr -d '[:space:]')
if [ "${PROC_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    PROCEDURE_EXISTS=true

    # Check if procedure is valid (compiled successfully)
    PROC_STATUS=$(oracle_query_raw "SELECT status FROM user_objects WHERE object_name = 'GIVE_DEPARTMENT_RAISE' AND object_type = 'PROCEDURE';" "hr" | tr -d '[:space:]')
    if [ "$PROC_STATUS" = "VALID" ]; then
        PROCEDURE_VALID=true
    fi

    # Check if procedure has an OUT parameter
    OUT_PARAM_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM user_arguments WHERE object_name = 'GIVE_DEPARTMENT_RAISE' AND in_out = 'OUT';" "hr" | tr -d '[:space:]')
    if [ "${OUT_PARAM_COUNT:-0}" -gt 0 ] 2>/dev/null; then
        PROCEDURE_HAS_OUT_PARAM=true
    fi
fi

# Check if procedure was newly created
INITIAL_PROC_COUNT=$(cat /tmp/initial_proc_count 2>/dev/null || echo "0")
CURRENT_PROC_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM user_procedures WHERE object_type = 'PROCEDURE';" "hr" | tr -d '[:space:]')
if [ "$CURRENT_PROC_COUNT" -gt "$INITIAL_PROC_COUNT" ] 2>/dev/null; then
    PROCEDURE_NEWLY_CREATED=true
fi

# Check if IT department salaries were updated (10% raise)
INITIAL_SALARY_SUM=$(cat /tmp/initial_it_salary_sum 2>/dev/null || echo "0")
CURRENT_SALARY_SUM=$(oracle_query_raw "SELECT SUM(salary) FROM employees WHERE department_id = 60;" "hr" | tr -d '[:space:]')

if [ -n "$CURRENT_SALARY_SUM" ] && [ -n "$INITIAL_SALARY_SUM" ] && [ "$INITIAL_SALARY_SUM" != "0" ]; then
    # Check if salaries changed at all
    if [ "$CURRENT_SALARY_SUM" != "$INITIAL_SALARY_SUM" ]; then
        SALARIES_UPDATED=true
    fi

    # Check if the increase is approximately 10%
    EXPECTED_SUM=$(echo "$INITIAL_SALARY_SUM * 1.1" | bc 2>/dev/null | cut -d'.' -f1)
    if [ -n "$EXPECTED_SUM" ]; then
        DIFF=$(echo "$CURRENT_SALARY_SUM - $EXPECTED_SUM" | bc 2>/dev/null)
        ABS_DIFF=${DIFF#-}
        # Allow tolerance of 100 (rounding differences)
        if [ "${ABS_DIFF:-9999}" -le 100 ] 2>/dev/null; then
            SALARY_INCREASE_CORRECT=true
        fi
    fi
fi

# Collect GUI evidence
GUI_EVIDENCE=$(collect_gui_evidence 2>/dev/null || echo '"gui_evidence": {"sql_history_count": 0, "mru_connection_count": 0, "window_title": "", "window_title_changed": false, "sqldev_oracle_sessions": 0}')

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "sql_developer_running": $SQL_DEVELOPER_RUNNING,
    "procedure_exists": $PROCEDURE_EXISTS,
    "procedure_valid": $PROCEDURE_VALID,
    "procedure_has_out_param": $PROCEDURE_HAS_OUT_PARAM,
    "procedure_newly_created": $PROCEDURE_NEWLY_CREATED,
    "salaries_updated": $SALARIES_UPDATED,
    "salary_increase_correct": $SALARY_INCREASE_CORRECT,
    "initial_salary_sum": ${INITIAL_SALARY_SUM:-0},
    "current_salary_sum": ${CURRENT_SALARY_SUM:-0},
    $GUI_EVIDENCE,
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/plsql_proc_result.json 2>/dev/null || sudo rm -f /tmp/plsql_proc_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/plsql_proc_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/plsql_proc_result.json
chmod 666 /tmp/plsql_proc_result.json 2>/dev/null || sudo chmod 666 /tmp/plsql_proc_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/plsql_proc_result.json"
cat /tmp/plsql_proc_result.json
echo "=== Export complete ==="
