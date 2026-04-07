#!/bin/bash
# Export script for RBAC Security Implementation task
# Verifies metadata and performs live access testing

set -e
echo "=== Exporting RBAC Security Results ==="

# Timestamp check
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Run Python Verification Script
python3 << PYEOF
import oracledb
import json
import os
import datetime

result = {
    "roles_exist": [],
    "users_exist": [],
    "role_assignments": {},
    "view_definitions": {},
    "privilege_grants": {},
    "live_access_tests": {},
    "report_file": {
        "exists": False,
        "size": 0,
        "content_preview": ""
    },
    "timestamp": datetime.datetime.now().isoformat()
}

dsn = "localhost:1521/XEPDB1"

try:
    # 1. METADATA CHECKS (as SYSTEM)
    conn_sys = oracledb.connect(user="system", password="OraclePassword123", dsn=dsn)
    cursor = conn_sys.cursor()

    # Check Roles
    target_roles = ["HR_READONLY", "HR_ANALYST", "HR_MANAGER"]
    for role in target_roles:
        cursor.execute("SELECT role FROM dba_roles WHERE role = :1", [role])
        if cursor.fetchone():
            result["roles_exist"].append(role)

    # Check Users
    target_users = ["APP_READER", "APP_ANALYST", "APP_MANAGER"]
    for user in target_users:
        cursor.execute("SELECT username FROM dba_users WHERE username = :1", [user])
        if cursor.fetchone():
            result["users_exist"].append(user)

    # Check Assignments
    cursor.execute("""
        SELECT grantee, granted_role 
        FROM dba_role_privs 
        WHERE grantee IN ('APP_READER', 'APP_ANALYST', 'APP_MANAGER')
    """)
    for row in cursor.fetchall():
        user, role = row
        if user not in result["role_assignments"]:
            result["role_assignments"][user] = []
        result["role_assignments"][user].append(role)

    # Check Table/View Privileges
    cursor.execute("""
        SELECT grantee, table_name, privilege
        FROM dba_tab_privs
        WHERE grantee IN ('HR_READONLY', 'HR_ANALYST', 'HR_MANAGER')
          AND owner = 'HR'
    """)
    for row in cursor.fetchall():
        grantee, table, priv = row
        key = f"{grantee}"
        if key not in result["privilege_grants"]:
            result["privilege_grants"][key] = []
        result["privilege_grants"][key].append(f"{priv} ON {table}")

    conn_sys.close()

    # 2. VIEW DEFINITION CHECKS (as HR)
    conn_hr = oracledb.connect(user="hr", password="hr123", dsn=dsn)
    cursor = conn_hr.cursor()

    # Check Views and Columns
    target_views = ["V_EMPLOYEE_PUBLIC", "V_DEPT_SUMMARY"]
    for view in target_views:
        cursor.execute("SELECT view_name FROM user_views WHERE view_name = :1", [view])
        if cursor.fetchone():
            result["view_definitions"][view] = {"exists": True, "columns": []}
            # Get columns
            cursor.execute("""
                SELECT column_name 
                FROM user_tab_columns 
                WHERE table_name = :1 
                ORDER BY column_id
            """, [view])
            cols = [r[0] for r in cursor.fetchall()]
            result["view_definitions"][view]["columns"] = cols
        else:
            result["view_definitions"][view] = {"exists": False}

    # Verify V_DEPT_SUMMARY aggregation (check row count)
    if result["view_definitions"]["V_DEPT_SUMMARY"]["exists"]:
        try:
            cursor.execute("SELECT COUNT(*) FROM V_DEPT_SUMMARY")
            count = cursor.fetchone()[0]
            result["view_definitions"]["V_DEPT_SUMMARY"]["row_count"] = count
        except:
            result["view_definitions"]["V_DEPT_SUMMARY"]["row_count"] = -1

    conn_hr.close()

    # 3. LIVE ACCESS TESTS (Try connecting as the new users)
    # We use a helper function to try connection and query
    def test_access(user, pwd, query, expect_success, description):
        try:
            c = oracledb.connect(user=user, password=pwd, dsn=dsn)
            cur = c.cursor()
            try:
                cur.execute(query)
                c.commit()
                status = "SUCCESS"
            except oracledb.DatabaseError as e:
                status = f"FAILED: {e}"
            c.close()
        except oracledb.DatabaseError as e:
            status = f"CONNECTION_FAILED: {e}"
        
        passed = (status == "SUCCESS") if expect_success else ("ORA-" in status or "FAILED" in status)
        return {"description": description, "status": status, "passed": passed}

    result["live_access_tests"]["reader_view_access"] = test_access(
        "APP_READER", "Reader#2024", "SELECT count(*) FROM HR.V_EMPLOYEE_PUBLIC", True, "Reader query public view")
    
    result["live_access_tests"]["reader_table_denial"] = test_access(
        "APP_READER", "Reader#2024", "SELECT count(*) FROM HR.EMPLOYEES", False, "Reader query employees table (should fail)")

    result["live_access_tests"]["manager_dml"] = test_access(
        "APP_MANAGER", "Manager#2024", 
        "UPDATE HR.DEPARTMENTS SET manager_id = manager_id WHERE department_id = 60", 
        True, "Manager UPDATE department")

except Exception as e:
    result["error"] = str(e)

# 4. REPORT FILE CHECK
report_path = "/home/ga/Desktop/security_report.txt"
if os.path.exists(report_path):
    result["report_file"]["exists"] = True
    result["report_file"]["size"] = os.path.getsize(report_path)
    try:
        with open(report_path, 'r') as f:
            result["report_file"]["content_preview"] = f.read(1000)
    except:
        pass

# Save to JSON
with open('/tmp/rbac_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result export complete.")
PYEOF

# Set permissions
chmod 666 /tmp/rbac_result.json 2>/dev/null || true
cat /tmp/rbac_result.json