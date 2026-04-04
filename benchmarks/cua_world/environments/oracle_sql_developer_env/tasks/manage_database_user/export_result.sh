#!/bin/bash
echo "=== Exporting Manage Database User results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Initialize
USER_EXISTS=false
USER_NEWLY_CREATED=false
HAS_CREATE_SESSION=false
SELECT_EMPLOYEES=false
SELECT_DEPARTMENTS=false
SELECT_JOBS=false
CAN_QUERY=false
SQL_DEVELOPER_RUNNING=false

# Check SQL Developer running
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "sql developer\|oracle sql"; then
    SQL_DEVELOPER_RUNNING=true
fi

# Check if REPORT_USER exists
USER_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_users WHERE username = 'REPORT_USER';" "system" | tr -d '[:space:]')
if [ "${USER_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    USER_EXISTS=true

    # Check CREATE SESSION privilege
    CS_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM dba_sys_privs WHERE grantee = 'REPORT_USER' AND privilege = 'CREATE SESSION';" "system" | tr -d '[:space:]')
    if [ "${CS_CHECK:-0}" -gt 0 ] 2>/dev/null; then
        HAS_CREATE_SESSION=true
    fi

    # Check SELECT grants on HR tables
    for tbl in EMPLOYEES DEPARTMENTS JOBS; do
        GRANT_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM dba_tab_privs WHERE grantee = 'REPORT_USER' AND owner = 'HR' AND table_name = '$tbl' AND privilege = 'SELECT';" "system" | tr -d '[:space:]')
        if [ "${GRANT_CHECK:-0}" -gt 0 ] 2>/dev/null; then
            case $tbl in
                EMPLOYEES) SELECT_EMPLOYEES=true ;;
                DEPARTMENTS) SELECT_DEPARTMENTS=true ;;
                JOBS) SELECT_JOBS=true ;;
            esac
        fi
    done

    # Test if REPORT_USER can actually query HR.EMPLOYEES
    QUERY_TEST=$(oracle_query_raw "SELECT COUNT(*) FROM hr.employees;" "report_user" 2>/dev/null | tr -d '[:space:]')
    if [ -n "$QUERY_TEST" ] && [ "$QUERY_TEST" -gt 0 ] 2>/dev/null; then
        CAN_QUERY=true
    fi
fi

# Check if user was newly created
INITIAL_USER_COUNT=$(cat /tmp/initial_user_count 2>/dev/null || echo "0")
CURRENT_USER_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM all_users WHERE username NOT IN ('SYS','SYSTEM','HR','ANONYMOUS','XDB');" "system" | tr -d '[:space:]')
if [ "$CURRENT_USER_COUNT" -gt "$INITIAL_USER_COUNT" ] 2>/dev/null; then
    USER_NEWLY_CREATED=true
fi

# Count granted privileges
GRANT_COUNT=0
if [ "$SELECT_EMPLOYEES" = "true" ]; then GRANT_COUNT=$((GRANT_COUNT + 1)); fi
if [ "$SELECT_DEPARTMENTS" = "true" ]; then GRANT_COUNT=$((GRANT_COUNT + 1)); fi
if [ "$SELECT_JOBS" = "true" ]; then GRANT_COUNT=$((GRANT_COUNT + 1)); fi

# Collect GUI evidence
GUI_EVIDENCE=$(collect_gui_evidence 2>/dev/null || echo '"gui_evidence": {"sql_history_count": 0, "mru_connection_count": 0, "window_title": "", "window_title_changed": false, "sqldev_oracle_sessions": 0}')

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "sql_developer_running": $SQL_DEVELOPER_RUNNING,
    "user_exists": $USER_EXISTS,
    "user_newly_created": $USER_NEWLY_CREATED,
    "has_create_session": $HAS_CREATE_SESSION,
    "select_employees": $SELECT_EMPLOYEES,
    "select_departments": $SELECT_DEPARTMENTS,
    "select_jobs": $SELECT_JOBS,
    "grant_count": $GRANT_COUNT,
    "can_query": $CAN_QUERY,
    $GUI_EVIDENCE,
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/manage_user_result.json 2>/dev/null || sudo rm -f /tmp/manage_user_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/manage_user_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/manage_user_result.json
chmod 666 /tmp/manage_user_result.json 2>/dev/null || sudo chmod 666 /tmp/manage_user_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/manage_user_result.json"
cat /tmp/manage_user_result.json
echo "=== Export complete ==="
