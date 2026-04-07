#!/bin/bash
# Export results for RBAC HR Security Implementation task
echo "=== Exporting RBAC Security Implementation Results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png ga

# Sanitize integer function
sanitize_int() { local val="$1" default="$2"; if [[ "$val" =~ ^[0-9]+$ ]]; then echo "$val"; else echo "$default"; fi; }

echo "Querying Oracle Data Dictionary for RBAC state..."

# 1. Check Roles
R_FULL=$(oracle_query_raw "SELECT COUNT(*) FROM dba_roles WHERE role = 'HR_FULL_ACCESS';" "system" | tr -d '[:space:]')
R_ANALYST=$(oracle_query_raw "SELECT COUNT(*) FROM dba_roles WHERE role = 'HR_ANALYST';" "system" | tr -d '[:space:]')
R_DEPT=$(oracle_query_raw "SELECT COUNT(*) FROM dba_roles WHERE role = 'DEPT_VIEWER';" "system" | tr -d '[:space:]')
R_READONLY=$(oracle_query_raw "SELECT COUNT(*) FROM dba_roles WHERE role = 'HR_READONLY';" "system" | tr -d '[:space:]')

# 2. Check Views
V_PUB_EXISTS=$(oracle_query_raw "SELECT COUNT(*) FROM dba_views WHERE owner='HR' AND view_name='EMPLOYEES_PUBLIC_VW';" "system" | tr -d '[:space:]')
# Does EMPLOYEES_PUBLIC_VW mask salary? (Count should be 0)
V_PUB_HAS_SALARY=$(oracle_query_raw "SELECT COUNT(*) FROM dba_tab_cols WHERE owner='HR' AND table_name='EMPLOYEES_PUBLIC_VW' AND column_name IN ('SALARY', 'COMMISSION_PCT');" "system" | tr -d '[:space:]')
# Is EMPLOYEES_PUBLIC_VW granted to PUBLIC?
V_PUB_GRANTED=$(oracle_query_raw "SELECT COUNT(*) FROM dba_tab_privs WHERE owner='HR' AND table_name='EMPLOYEES_PUBLIC_VW' AND grantee='PUBLIC';" "system" | tr -d '[:space:]')

V_COMP_EXISTS=$(oracle_query_raw "SELECT COUNT(*) FROM dba_views WHERE owner='HR' AND view_name='COMPENSATION_AUDIT_VW';" "system" | tr -d '[:space:]')
# Does COMPENSATION_AUDIT_VW have the right columns? (Count should be 2)
V_COMP_HAS_COLS=$(oracle_query_raw "SELECT COUNT(*) FROM dba_tab_cols WHERE owner='HR' AND table_name='COMPENSATION_AUDIT_VW' AND column_name IN ('SALARY', 'DEPARTMENT_NAME');" "system" | tr -d '[:space:]')
# Is COMPENSATION_AUDIT_VW granted to the right roles?
V_COMP_GRANTED=$(oracle_query_raw "SELECT COUNT(*) FROM dba_tab_privs WHERE owner='HR' AND table_name='COMPENSATION_AUDIT_VW' AND grantee IN ('HR_FULL_ACCESS', 'HR_ANALYST');" "system" | tr -d '[:space:]')

# 3. Check Users
U_MGR=$(oracle_query_raw "SELECT COUNT(*) FROM dba_users WHERE username = 'TEST_HR_MANAGER';" "system" | tr -d '[:space:]')
U_ANA=$(oracle_query_raw "SELECT COUNT(*) FROM dba_users WHERE username = 'TEST_HR_ANALYST';" "system" | tr -d '[:space:]')
U_DEPT=$(oracle_query_raw "SELECT COUNT(*) FROM dba_users WHERE username = 'TEST_DEPT_MGR';" "system" | tr -d '[:space:]')
U_READ=$(oracle_query_raw "SELECT COUNT(*) FROM dba_users WHERE username = 'TEST_READONLY';" "system" | tr -d '[:space:]')

# 4. Check User-Role Assignments
G_MGR_ROLE=$(oracle_query_raw "SELECT COUNT(*) FROM dba_role_privs WHERE grantee='TEST_HR_MANAGER' AND granted_role='HR_FULL_ACCESS';" "system" | tr -d '[:space:]')
G_ANA_ROLE=$(oracle_query_raw "SELECT COUNT(*) FROM dba_role_privs WHERE grantee='TEST_HR_ANALYST' AND granted_role='HR_ANALYST';" "system" | tr -d '[:space:]')
G_DEPT_ROLE=$(oracle_query_raw "SELECT COUNT(*) FROM dba_role_privs WHERE grantee='TEST_DEPT_MGR' AND granted_role='DEPT_VIEWER';" "system" | tr -d '[:space:]')
G_READ_ROLE=$(oracle_query_raw "SELECT COUNT(*) FROM dba_role_privs WHERE grantee='TEST_READONLY' AND granted_role='HR_READONLY';" "system" | tr -d '[:space:]')

# 5. Check Table Privileges on HR Schema
PRIV_FULL_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM dba_tab_privs WHERE grantee='HR_FULL_ACCESS' AND owner='HR';" "system" | tr -d '[:space:]')
PRIV_ANA_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM dba_tab_privs WHERE grantee='HR_ANALYST' AND owner='HR';" "system" | tr -d '[:space:]')
PRIV_DEPT_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM dba_tab_privs WHERE grantee='DEPT_VIEWER' AND owner='HR';" "system" | tr -d '[:space:]')
PRIV_READ_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM dba_tab_privs WHERE grantee='HR_READONLY' AND owner='HR';" "system" | tr -d '[:space:]')

# 6. Check Audit Policy
AUDIT_NAME_EXISTS=$(oracle_query_raw "SELECT COUNT(*) FROM audit_unified_policies WHERE policy_name='SALARY_ACCESS_AUDIT';" "system" | tr -d '[:space:]')
AUDIT_TARGET_CORRECT=$(oracle_query_raw "SELECT COUNT(*) FROM audit_unified_policies WHERE policy_name='SALARY_ACCESS_AUDIT' AND object_schema='HR' AND object_name='EMPLOYEES';" "system" | tr -d '[:space:]')
AUDIT_ENABLED=$(oracle_query_raw "SELECT COUNT(*) FROM audit_unified_enabled_policies WHERE policy_name='SALARY_ACCESS_AUDIT';" "system" | tr -d '[:space:]')

# 7. Collect GUI usage evidence
GUI_EVIDENCE=$(collect_gui_evidence)

# Create JSON payload
TEMP_JSON=$(mktemp /tmp/rbac_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "roles": {
        "HR_FULL_ACCESS": $(sanitize_int "$R_FULL" 0),
        "HR_ANALYST": $(sanitize_int "$R_ANALYST" 0),
        "DEPT_VIEWER": $(sanitize_int "$R_DEPT" 0),
        "HR_READONLY": $(sanitize_int "$R_READONLY" 0)
    },
    "views": {
        "EMPLOYEES_PUBLIC_VW_EXISTS": $(sanitize_int "$V_PUB_EXISTS" 0),
        "EMPLOYEES_PUBLIC_VW_HAS_SALARY": $(sanitize_int "$V_PUB_HAS_SALARY" 0),
        "EMPLOYEES_PUBLIC_VW_PUBLIC_GRANT": $(sanitize_int "$V_PUB_GRANTED" 0),
        "COMPENSATION_AUDIT_VW_EXISTS": $(sanitize_int "$V_COMP_EXISTS" 0),
        "COMPENSATION_AUDIT_VW_HAS_COLS": $(sanitize_int "$V_COMP_HAS_COLS" 0),
        "COMPENSATION_AUDIT_VW_GRANTED": $(sanitize_int "$V_COMP_GRANTED" 0)
    },
    "users": {
        "TEST_HR_MANAGER": $(sanitize_int "$U_MGR" 0),
        "TEST_HR_ANALYST": $(sanitize_int "$U_ANA" 0),
        "TEST_DEPT_MGR": $(sanitize_int "$U_DEPT" 0),
        "TEST_READONLY": $(sanitize_int "$U_READ" 0)
    },
    "role_assignments": {
        "TEST_HR_MANAGER_HAS_FULL": $(sanitize_int "$G_MGR_ROLE" 0),
        "TEST_HR_ANALYST_HAS_ANA": $(sanitize_int "$G_ANA_ROLE" 0),
        "TEST_DEPT_MGR_HAS_DEPT": $(sanitize_int "$G_DEPT_ROLE" 0),
        "TEST_READONLY_HAS_READ": $(sanitize_int "$G_READ_ROLE" 0)
    },
    "privilege_counts": {
        "HR_FULL_ACCESS": $(sanitize_int "$PRIV_FULL_COUNT" 0),
        "HR_ANALYST": $(sanitize_int "$PRIV_ANA_COUNT" 0),
        "DEPT_VIEWER": $(sanitize_int "$PRIV_DEPT_COUNT" 0),
        "HR_READONLY": $(sanitize_int "$PRIV_READ_COUNT" 0)
    },
    "audit_policy": {
        "exists": $(sanitize_int "$AUDIT_NAME_EXISTS" 0),
        "target_correct": $(sanitize_int "$AUDIT_TARGET_CORRECT" 0),
        "enabled": $(sanitize_int "$AUDIT_ENABLED" 0)
    },
    $GUI_EVIDENCE
}
EOF

# Move to final location
rm -f /tmp/rbac_result.json 2>/dev/null || sudo rm -f /tmp/rbac_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/rbac_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/rbac_result.json
chmod 666 /tmp/rbac_result.json 2>/dev/null || sudo chmod 666 /tmp/rbac_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/rbac_result.json"
cat /tmp/rbac_result.json
echo "=== Export Complete ==="