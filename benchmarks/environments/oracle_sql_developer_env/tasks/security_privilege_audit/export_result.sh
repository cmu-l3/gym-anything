#!/bin/bash
echo "=== Exporting Security Privilege Audit Result ==="
source /workspace/scripts/task_utils.sh

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# -------------------------------------------------------
# DEV_USER checks: DBA role should be gone
# -------------------------------------------------------
DEV_HAS_DBA=$(oracle_query_raw "SELECT COUNT(*) FROM dba_role_privs WHERE grantee='DEV_USER' AND granted_role='DBA'" "system")
DEV_SYS_PRIV_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM dba_sys_privs WHERE grantee='DEV_USER'" "system")
DEV_ROLE_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM dba_role_privs WHERE grantee='DEV_USER'" "system")
DEV_EXISTS=$(oracle_query_raw "SELECT COUNT(*) FROM dba_users WHERE username='DEV_USER'" "system")

# -------------------------------------------------------
# REPORT_USER2 checks: CREATE TABLE + SELECT ANY TABLE should be gone
# -------------------------------------------------------
REPORT_HAS_CREATE_TABLE=$(oracle_query_raw "SELECT COUNT(*) FROM dba_sys_privs WHERE grantee='REPORT_USER2' AND privilege='CREATE TABLE'" "system")
REPORT_HAS_SELECT_ANY=$(oracle_query_raw "SELECT COUNT(*) FROM dba_sys_privs WHERE grantee='REPORT_USER2' AND privilege='SELECT ANY TABLE'" "system")
REPORT_EXISTS=$(oracle_query_raw "SELECT COUNT(*) FROM dba_users WHERE username='REPORT_USER2'" "system")

# -------------------------------------------------------
# ANALYST_USER checks: ALTER SYSTEM + other excess should be gone
# -------------------------------------------------------
ANALYST_HAS_ALTER_SYSTEM=$(oracle_query_raw "SELECT COUNT(*) FROM dba_sys_privs WHERE grantee='ANALYST_USER' AND privilege='ALTER SYSTEM'" "system")
ANALYST_HAS_SELECT_DICT=$(oracle_query_raw "SELECT COUNT(*) FROM dba_sys_privs WHERE grantee='ANALYST_USER' AND privilege='SELECT ANY DICTIONARY'" "system")
ANALYST_HAS_CREATE_TABLE=$(oracle_query_raw "SELECT COUNT(*) FROM dba_sys_privs WHERE grantee='ANALYST_USER' AND privilege='CREATE TABLE'" "system")
ANALYST_EXISTS=$(oracle_query_raw "SELECT COUNT(*) FROM dba_users WHERE username='ANALYST_USER'" "system")

# -------------------------------------------------------
# APP_USER checks: RESOURCE role + UNLIMITED TABLESPACE should be gone
# -------------------------------------------------------
APP_HAS_RESOURCE=$(oracle_query_raw "SELECT COUNT(*) FROM dba_role_privs WHERE grantee='APP_USER' AND granted_role='RESOURCE'" "system")
APP_HAS_UNLIMITED=$(oracle_query_raw "SELECT COUNT(*) FROM dba_sys_privs WHERE grantee='APP_USER' AND privilege='UNLIMITED TABLESPACE'" "system")
APP_EXISTS=$(oracle_query_raw "SELECT COUNT(*) FROM dba_users WHERE username='APP_USER'" "system")

# -------------------------------------------------------
# LEGACY_USER checks: account should be LOCKED
# -------------------------------------------------------
LEGACY_STATUS=$(oracle_query_raw "SELECT account_status FROM dba_users WHERE username='LEGACY_USER'" "system")
LEGACY_EXISTS=$(oracle_query_raw "SELECT COUNT(*) FROM dba_users WHERE username='LEGACY_USER'" "system")

# -------------------------------------------------------
# Unified Audit policy checks
# -------------------------------------------------------
AUDIT_POLICY_EXISTS=$(oracle_query_raw "SELECT COUNT(*) FROM audit_unified_policies WHERE policy_name='PRIVILEGE_ESCALATION_AUDIT'" "system")
AUDIT_POLICY_ENABLED=$(oracle_query_raw "SELECT COUNT(*) FROM audit_unified_enabled_policies WHERE policy_name='PRIVILEGE_ESCALATION_AUDIT'" "system")
AUDIT_PRIV_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM audit_unified_policies WHERE policy_name='PRIVILEGE_ESCALATION_AUDIT'" "system")

# Count how many of the 5 required privileges are covered in the audit policy
# Check for each privilege action in the policy
AUDIT_HAS_GRANT=$(oracle_query_raw "SELECT COUNT(*) FROM audit_unified_policy_actions WHERE policy_name='PRIVILEGE_ESCALATION_AUDIT' AND privilege_name='GRANT ANY PRIVILEGE'" "system")
AUDIT_HAS_CREATE_USER=$(oracle_query_raw "SELECT COUNT(*) FROM audit_unified_policy_actions WHERE policy_name='PRIVILEGE_ESCALATION_AUDIT' AND privilege_name='CREATE USER'" "system")
AUDIT_HAS_DROP_USER=$(oracle_query_raw "SELECT COUNT(*) FROM audit_unified_policy_actions WHERE policy_name='PRIVILEGE_ESCALATION_AUDIT' AND privilege_name='DROP USER'" "system")
AUDIT_HAS_ALTER_USER=$(oracle_query_raw "SELECT COUNT(*) FROM audit_unified_policy_actions WHERE policy_name='PRIVILEGE_ESCALATION_AUDIT' AND privilege_name='ALTER USER'" "system")
AUDIT_HAS_CREATE_ROLE=$(oracle_query_raw "SELECT COUNT(*) FROM audit_unified_policy_actions WHERE policy_name='PRIVILEGE_ESCALATION_AUDIT' AND privilege_name='CREATE ROLE'" "system")

# -------------------------------------------------------
# Security report file check
# -------------------------------------------------------
REPORT_FILE="/home/ga/Documents/exports/security_remediation.txt"
REPORT_EXISTS=false
REPORT_SIZE=0
REPORT_MENTIONS_DEV=false
REPORT_MENTIONS_AUDIT=false

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS=true
    REPORT_SIZE=$(wc -c < "$REPORT_FILE")
    if grep -qi "dev_user\|DEV_USER\|dev user" "$REPORT_FILE"; then
        REPORT_MENTIONS_DEV=true
    fi
    if grep -qi "audit\|PRIVILEGE_ESCALATION\|unified audit" "$REPORT_FILE"; then
        REPORT_MENTIONS_AUDIT=true
    fi
fi

# -------------------------------------------------------
# Collect GUI evidence
# -------------------------------------------------------
GUI_EVIDENCE=$(collect_gui_evidence 2>/dev/null || echo '"gui_evidence": {"sql_history_count": 0, "mru_connection_count": 0, "window_title": "", "window_title_changed": false, "sqldev_oracle_sessions": 0}')

# -------------------------------------------------------
# Build result JSON
# -------------------------------------------------------
cat > /tmp/security_privilege_audit_result.json << EOF
{
  "dev_user_exists": $([ "${DEV_EXISTS:-0}" -gt 0 ] && echo true || echo false),
  "dev_has_dba": $([ "${DEV_HAS_DBA:-0}" -gt 0 ] && echo true || echo false),
  "dev_sys_priv_count": ${DEV_SYS_PRIV_COUNT:-0},
  "dev_role_count": ${DEV_ROLE_COUNT:-0},

  "report_user2_exists": $([ "${REPORT_EXISTS:-0}" -gt 0 ] && echo true || echo false),
  "report_has_create_table": $([ "${REPORT_HAS_CREATE_TABLE:-0}" -gt 0 ] && echo true || echo false),
  "report_has_select_any": $([ "${REPORT_HAS_SELECT_ANY:-0}" -gt 0 ] && echo true || echo false),

  "analyst_user_exists": $([ "${ANALYST_EXISTS:-0}" -gt 0 ] && echo true || echo false),
  "analyst_has_alter_system": $([ "${ANALYST_HAS_ALTER_SYSTEM:-0}" -gt 0 ] && echo true || echo false),
  "analyst_has_select_dict": $([ "${ANALYST_HAS_SELECT_DICT:-0}" -gt 0 ] && echo true || echo false),
  "analyst_has_create_table": $([ "${ANALYST_HAS_CREATE_TABLE:-0}" -gt 0 ] && echo true || echo false),

  "app_user_exists": $([ "${APP_EXISTS:-0}" -gt 0 ] && echo true || echo false),
  "app_has_resource": $([ "${APP_HAS_RESOURCE:-0}" -gt 0 ] && echo true || echo false),
  "app_has_unlimited_tablespace": $([ "${APP_HAS_UNLIMITED:-0}" -gt 0 ] && echo true || echo false),

  "legacy_user_exists": $([ "${LEGACY_EXISTS:-0}" -gt 0 ] && echo true || echo false),
  "legacy_account_status": "${LEGACY_STATUS}",
  "legacy_is_locked": $(echo "${LEGACY_STATUS}" | grep -qi "LOCKED" && echo true || echo false),

  "audit_policy_exists": $([ "${AUDIT_POLICY_EXISTS:-0}" -gt 0 ] && echo true || echo false),
  "audit_policy_enabled": $([ "${AUDIT_POLICY_ENABLED:-0}" -gt 0 ] && echo true || echo false),
  "audit_has_grant_any_privilege": $([ "${AUDIT_HAS_GRANT:-0}" -gt 0 ] && echo true || echo false),
  "audit_has_create_user": $([ "${AUDIT_HAS_CREATE_USER:-0}" -gt 0 ] && echo true || echo false),
  "audit_has_drop_user": $([ "${AUDIT_HAS_DROP_USER:-0}" -gt 0 ] && echo true || echo false),
  "audit_has_alter_user": $([ "${AUDIT_HAS_ALTER_USER:-0}" -gt 0 ] && echo true || echo false),
  "audit_has_create_role": $([ "${AUDIT_HAS_CREATE_ROLE:-0}" -gt 0 ] && echo true || echo false),

  "report_exists": $REPORT_EXISTS,
  "report_size": $REPORT_SIZE,
  "report_mentions_dev_user": $REPORT_MENTIONS_DEV,
  "report_mentions_audit": $REPORT_MENTIONS_AUDIT,

  $GUI_EVIDENCE
}
EOF

chmod 666 /tmp/security_privilege_audit_result.json
echo "=== Security Privilege Audit Export Complete ==="
echo "Result saved to /tmp/security_privilege_audit_result.json"
cat /tmp/security_privilege_audit_result.json
