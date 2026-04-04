#!/bin/bash
echo "=== Setting up Security Privilege Audit Task ==="
source /workspace/scripts/task_utils.sh

# -------------------------------------------------------
# Drop existing misconfigured users if they already exist
# -------------------------------------------------------
oracle_query "BEGIN
  FOR u IN (SELECT username FROM dba_users WHERE username IN ('DEV_USER','REPORT_USER2','ANALYST_USER','APP_USER','LEGACY_USER')) LOOP
    EXECUTE IMMEDIATE 'DROP USER ' || u.username || ' CASCADE';
  END LOOP;
END;" "system" "OraclePassword123"

# Drop any existing audit policy from prior runs
oracle_query "BEGIN
  FOR p IN (SELECT policy_name FROM audit_unified_policies WHERE policy_name = 'PRIVILEGE_ESCALATION_AUDIT') LOOP
    EXECUTE IMMEDIATE 'NOAUDIT POLICY ' || p.policy_name;
    EXECUTE IMMEDIATE 'DROP AUDIT POLICY ' || p.policy_name;
  END LOOP;
END;" "system" "OraclePassword123"

echo "Cleaned up prior state."

# -------------------------------------------------------
# Create DEV_USER with dangerously over-privileged DBA role
# A developer who was given DBA 'temporarily' and never revoked
# -------------------------------------------------------
oracle_query "CREATE USER dev_user IDENTIFIED BY DevPass2024" "system" "OraclePassword123"
oracle_query "GRANT DBA TO dev_user" "system" "OraclePassword123"
oracle_query "GRANT CREATE SESSION TO dev_user" "system" "OraclePassword123"
echo "DEV_USER created with DBA role."

# -------------------------------------------------------
# Create REPORT_USER2 with CREATE TABLE and SELECT ANY TABLE
# A reporting analyst who was given broad SELECT + DDL rights
# -------------------------------------------------------
oracle_query "CREATE USER report_user2 IDENTIFIED BY ReportPass2024" "system" "OraclePassword123"
oracle_query "GRANT CREATE SESSION TO report_user2" "system" "OraclePassword123"
oracle_query "GRANT CREATE TABLE TO report_user2" "system" "OraclePassword123"
oracle_query "GRANT SELECT ANY TABLE TO report_user2" "system" "OraclePassword123"
oracle_query "GRANT UNLIMITED TABLESPACE TO report_user2" "system" "OraclePassword123"
echo "REPORT_USER2 created with CREATE TABLE and SELECT ANY TABLE."

# -------------------------------------------------------
# Create ANALYST_USER with direct system privileges
# including ALTER SYSTEM which is extremely dangerous
# -------------------------------------------------------
oracle_query "CREATE USER analyst_user IDENTIFIED BY AnalystPass2024" "system" "OraclePassword123"
oracle_query "GRANT CREATE SESSION TO analyst_user" "system" "OraclePassword123"
oracle_query "GRANT CREATE VIEW TO analyst_user" "system" "OraclePassword123"
oracle_query "GRANT CREATE TABLE TO analyst_user" "system" "OraclePassword123"
oracle_query "GRANT ALTER SYSTEM TO analyst_user" "system" "OraclePassword123"
oracle_query "GRANT SELECT ANY DICTIONARY TO analyst_user" "system" "OraclePassword123"
echo "ANALYST_USER created with dangerous ALTER SYSTEM privilege."

# -------------------------------------------------------
# Create APP_USER with RESOURCE role and UNLIMITED TABLESPACE
# An application account that should use only stored procedures
# -------------------------------------------------------
oracle_query "CREATE USER app_user IDENTIFIED BY AppPass2024" "system" "OraclePassword123"
oracle_query "GRANT CREATE SESSION TO app_user" "system" "OraclePassword123"
oracle_query "GRANT RESOURCE TO app_user" "system" "OraclePassword123"
oracle_query "GRANT UNLIMITED TABLESPACE TO app_user" "system" "OraclePassword123"
echo "APP_USER created with RESOURCE role and UNLIMITED TABLESPACE."

# -------------------------------------------------------
# Create LEGACY_USER with DBA role — a retired system account
# Password expired, account still OPEN (should be LOCKED)
# -------------------------------------------------------
oracle_query "CREATE USER legacy_user IDENTIFIED BY LegacyPass2024 PASSWORD EXPIRE" "system" "OraclePassword123"
oracle_query "GRANT DBA TO legacy_user" "system" "OraclePassword123"
oracle_query "GRANT CREATE SESSION TO legacy_user" "system" "OraclePassword123"
echo "LEGACY_USER created with DBA role, password expired but account OPEN."

# -------------------------------------------------------
# Ensure exports directory exists
# -------------------------------------------------------
mkdir -p /home/ga/Documents/exports
chown ga:ga /home/ga/Documents/exports 2>/dev/null || true

# -------------------------------------------------------
# Record baseline: how many system privs each user currently has
# -------------------------------------------------------
DEV_PRIV_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM dba_sys_privs WHERE grantee='DEV_USER'" "system/OraclePassword123")
REPORT_PRIV_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM dba_sys_privs WHERE grantee='REPORT_USER2'" "system/OraclePassword123")
ANALYST_PRIV_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM dba_sys_privs WHERE grantee='ANALYST_USER'" "system/OraclePassword123")
APP_PRIV_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM dba_sys_privs WHERE grantee='APP_USER'" "system/OraclePassword123")
LEGACY_PRIV_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM dba_sys_privs WHERE grantee='LEGACY_USER'" "system/OraclePassword123")

echo "${DEV_PRIV_COUNT:-0}" > /tmp/initial_dev_priv_count
echo "${REPORT_PRIV_COUNT:-0}" > /tmp/initial_report_priv_count
echo "${ANALYST_PRIV_COUNT:-0}" > /tmp/initial_analyst_priv_count
echo "${APP_PRIV_COUNT:-0}" > /tmp/initial_app_priv_count
echo "${LEGACY_PRIV_COUNT:-0}" > /tmp/initial_legacy_priv_count

echo "Baseline privilege counts recorded."
echo "  DEV_USER:       ${DEV_PRIV_COUNT:-0} system privs"
echo "  REPORT_USER2:   ${REPORT_PRIV_COUNT:-0} system privs"
echo "  ANALYST_USER:   ${ANALYST_PRIV_COUNT:-0} system privs"
echo "  APP_USER:       ${APP_PRIV_COUNT:-0} system privs"
echo "  LEGACY_USER:    ${LEGACY_PRIV_COUNT:-0} system privs"

# -------------------------------------------------------
# Record task start time
# -------------------------------------------------------
date +%s > /tmp/task_start_timestamp

# -------------------------------------------------------
# Ensure SQL Developer is running
# -------------------------------------------------------
ensure_hr_connection

SQLDEVELOPER_PID=$(pgrep -f "sqldeveloper" | head -1)
if [ -z "$SQLDEVELOPER_PID" ]; then
    echo "Starting SQL Developer..."
    sudo -u ga DISPLAY=:1 /opt/sqldeveloper/sqldeveloper.sh &
    sleep 15
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Security Privilege Audit Setup Complete ==="
echo "Five misconfigured Oracle users are ready for remediation."
echo "Users: DEV_USER (DBA), REPORT_USER2 (SELECT ANY TABLE), ANALYST_USER (ALTER SYSTEM),"
echo "       APP_USER (RESOURCE), LEGACY_USER (DBA + expired, open)"
