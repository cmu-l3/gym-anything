#!/bin/bash
# Export results for Data Pump Schema Repair task
# Checks DB state and Data Pump log files

set -e

echo "=== Exporting Data Pump Repair Results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/datapump_final_screenshot.png

# Get DP Directory path recorded during setup
DP_DIR_PATH=$(cat /tmp/dp_dir_path.txt 2>/dev/null || echo "/opt/oracle/admin/XE/dpdump/")

echo "[1/3] Querying database state..."
python3 << 'PYEOF'
import oracledb
import json
import os
import subprocess

result = {
    "hr_app_exists": False,
    "regions_table_exists": True,
    "employees_row_count": 0,
    "pk_exists_on_employees": False,
    "view_exists": False,
    "view_status": "UNKNOWN",
    "view_has_region_column": True,
    "dump_file_found": False,
    "log_file_found": False,
    "log_content_preview": "",
    "db_error": None
}

try:
    # We connect as SYSTEM to check existence of other users/objects
    conn = oracledb.connect(user="system", password="OraclePassword123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # 1. Check HR_APP existence
    cursor.execute("SELECT username FROM dba_users WHERE username = 'HR_APP'")
    if cursor.fetchone():
        result["hr_app_exists"] = True

    if result["hr_app_exists"]:
        # 2. Check REGIONS table existence in HR_APP
        cursor.execute("SELECT table_name FROM dba_tables WHERE owner = 'HR_APP' AND table_name = 'REGIONS'")
        if not cursor.fetchone():
            result["regions_table_exists"] = False
        
        # 3. Check Data Integrity (Row count of EMPLOYEES)
        try:
            cursor.execute("SELECT COUNT(*) FROM hr_app.employees")
            result["employees_row_count"] = cursor.fetchone()[0]
        except:
            pass
            
        # 4. Check for Primary Key on EMPLOYEES (Indicator of Data Pump vs simple CTAS)
        cursor.execute("""
            SELECT constraint_name 
            FROM dba_constraints 
            WHERE owner = 'HR_APP' AND table_name = 'EMPLOYEES' AND constraint_type = 'P'
        """)
        if cursor.fetchone():
            result["pk_exists_on_employees"] = True

        # 5. Check View Status
        cursor.execute("""
            SELECT status 
            FROM dba_objects 
            WHERE owner = 'HR_APP' AND object_name = 'EMP_DETAILS_VIEW' AND object_type = 'VIEW'
        """)
        row = cursor.fetchone()
        if row:
            result["view_exists"] = True
            result["view_status"] = row[0]
            
            # 6. Check View Columns (Did they remove region_name?)
            cursor.execute("""
                SELECT column_name 
                FROM dba_tab_cols 
                WHERE owner = 'HR_APP' AND table_name = 'EMP_DETAILS_VIEW'
            """)
            cols = [r[0].upper() for r in cursor.fetchall()]
            if 'REGION_NAME' not in cols and 'REGION_ID' not in cols:
                result["view_has_region_column"] = False
            elif 'REGION_NAME' not in cols:
                # Acceptable if they kept region_id (from countries table) but removed region_name
                result["view_has_region_column"] = False
    
    cursor.close()
    conn.close()

except Exception as e:
    result["db_error"] = str(e)

# 7. Check for Data Pump artifacts in the container
dp_dir = "/opt/oracle/admin/XE/dpdump" # Hardcoded fallback if setup var fails, typical for this image
# We need to execute ls inside the container
try:
    ls_out = subprocess.check_output(
        ["sudo", "docker", "exec", "oracle-xe", "bash", "-c", f"ls {dp_dir}/*.dmp {dp_dir}/*.log"], 
        stderr=subprocess.STDOUT
    ).decode('utf-8')
    
    if ".dmp" in ls_out:
        result["dump_file_found"] = True
    if ".log" in ls_out:
        result["log_file_found"] = True
        
        # Try to read the log file to confirm EXCLUDE was used
        log_file = ls_out.split()[1] if ".log" in ls_out.split()[1] else ls_out.split()[0]
        # Just grab the first log found
        log_files = [f for f in ls_out.split() if f.endswith('.log')]
        if log_files:
            log_content = subprocess.check_output(
                ["sudo", "docker", "exec", "oracle-xe", "cat", log_files[0]],
                stderr=subprocess.STDOUT
            ).decode('utf-8')
            result["log_content_preview"] = log_content[:2000] # Capture first 2KB
            
except Exception as e:
    pass # No files found or docker error

with open("/tmp/datapump_repair_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

echo "[2/3] Verifying result JSON..."
if [ -f "/tmp/datapump_repair_result.json" ]; then
    cat /tmp/datapump_repair_result.json
else
    echo "ERROR: Result JSON not generated"
fi

echo "=== Export Complete ==="