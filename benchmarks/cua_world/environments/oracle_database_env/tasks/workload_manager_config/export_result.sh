#!/bin/bash
# Export script for Workload Manager Configuration task
# Queries Oracle Data Dictionary to verify configuration

set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting Workload Manager Results ==="

# Take final screenshot
take_screenshot /tmp/task_final.png

# Timestamp check
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# Use Python to query Oracle and export JSON
# We use Python because parsing SQLPlus text output with complex tables is fragile
cat > /tmp/export_workload.py << 'EOF'
import oracledb
import json
import os
import sys

# Connection details
dsn = "localhost:1521/XEPDB1"
user = "system"
password = "OraclePassword123"

result = {
    "plan_exists": False,
    "plan_enabled": False,
    "active_plan": "",
    "consumer_groups": [],
    "directives": [],
    "mappings": [],
    "privileges": [],
    "error": None
}

try:
    conn = oracledb.connect(user=user, password=password, dsn=dsn)
    cursor = conn.cursor()

    # 1. Check Active Plan
    cursor.execute("SELECT value FROM v$parameter WHERE name = 'resource_manager_plan'")
    row = cursor.fetchone()
    if row:
        result["active_plan"] = row[0]
        if row[0] and row[0].upper() == 'STABILITY_PLAN':
            result["plan_enabled"] = True

    # 2. Check Plan Existence
    cursor.execute("SELECT plan FROM dba_rsrc_plans WHERE plan = 'STABILITY_PLAN'")
    if cursor.fetchone():
        result["plan_exists"] = True

    # 3. Check Consumer Groups
    cursor.execute("SELECT consumer_group FROM dba_rsrc_consumer_groups WHERE consumer_group IN ('CRITICAL_APP_CG', 'BATCH_REPORT_CG')")
    result["consumer_groups"] = [r[0] for r in cursor.fetchall()]

    # 4. Check Directives (CPU % and Switching)
    # Note: mgmt_p1 is CPU % at level 1
    cursor.execute("""
        SELECT group_or_subplan, mgmt_p1, switch_time, switch_group 
        FROM dba_rsrc_plan_directives 
        WHERE plan = 'STABILITY_PLAN'
    """)
    for r in cursor.fetchall():
        result["directives"].append({
            "group": r[0],
            "cpu_p1": r[1],
            "switch_time": r[2],
            "switch_group": r[3]
        })

    # 5. Check User Mappings
    cursor.execute("""
        SELECT attribute, value, consumer_group 
        FROM dba_rsrc_group_mappings 
        WHERE attribute = 'ORACLE_USER' 
          AND value IN ('APP_USER', 'RPT_USER')
    """)
    for r in cursor.fetchall():
        result["mappings"].append({
            "user": r[1],
            "group": r[2]
        })

    # 6. Check Switch Privileges
    cursor.execute("""
        SELECT grantee, granted_group, initial_group
        FROM dba_rsrc_consumer_group_privs
        WHERE grantee IN ('APP_USER', 'RPT_USER')
    """)
    for r in cursor.fetchall():
        result["privileges"].append({
            "user": r[0],
            "group": r[1],
            "is_initial": r[2] 
        })

    cursor.close()
    conn.close()

except Exception as e:
    result["error"] = str(e)

# Write to file
with open("/tmp/workload_manager_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export complete.")
EOF

# Execute the python script inside the container
# Note: The environment has python3 and oracledb installed
echo "Running export script..."
sudo docker exec -i "$ORACLE_CONTAINER" python3 - < /tmp/export_workload.py

# Copy the result out of the docker container to the VM's /tmp for the verifier to read via copy_from_env
# Actually, the python script ran inside docker, so the file is in docker /tmp/
# We need to copy it to the VM /tmp/
sudo docker cp "$ORACLE_CONTAINER":/tmp/workload_manager_result.json /tmp/workload_manager_result.json
chmod 666 /tmp/workload_manager_result.json

echo "=== Export Complete ==="
cat /tmp/workload_manager_result.json