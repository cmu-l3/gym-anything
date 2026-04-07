#!/bin/bash
# Export results for Partition Audit Log task

set -e

echo "=== Exporting Partition Audit Log Results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/partition_task_final_screenshot.png

# Read baseline
INITIAL_COUNT=$(cat /tmp/initial_audit_count.txt 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Python script to inspect database state
python3 << PYEOF
import oracledb
import json
import os
import datetime

result = {
    "initial_count": int("${INITIAL_COUNT}"),
    "current_count": 0,
    "is_partitioned": False,
    "partition_count": 0,
    "partition_names": [],
    "partition_row_counts": {},
    "indexes": [],
    "local_index_count": 0,
    "summary_file_exists": False,
    "summary_file_content": "",
    "export_timestamp": datetime.datetime.now().isoformat()
}

try:
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # 1. Check table existence and row count
    cursor.execute("SELECT COUNT(*) FROM employee_audit_log")
    result["current_count"] = cursor.fetchone()[0]

    # 2. Check partitioning status
    cursor.execute("""
        SELECT partitioned
        FROM user_tables
        WHERE table_name = 'EMPLOYEE_AUDIT_LOG'
    """)
    row = cursor.fetchone()
    if row and row[0] == 'YES':
        result["is_partitioned"] = True

        # Get partition details
        cursor.execute("""
            SELECT partition_name, high_value
            FROM user_tab_partitions
            WHERE table_name = 'EMPLOYEE_AUDIT_LOG'
            ORDER BY partition_position
        """)
        partitions = cursor.fetchall()
        result["partition_count"] = len(partitions)
        result["partition_names"] = [p[0] for p in partitions]

        # Get row counts per partition (requires stats or direct query)
        # We'll do direct count for accuracy
        for p_name in result["partition_names"]:
            try:
                cursor.execute(f"SELECT COUNT(*) FROM employee_audit_log PARTITION ({p_name})")
                count = cursor.fetchone()[0]
                result["partition_row_counts"][p_name] = count
            except:
                result["partition_row_counts"][p_name] = -1

    # 3. Check Indexes
    cursor.execute("""
        SELECT index_name, partitioned
        FROM user_indexes
        WHERE table_name = 'EMPLOYEE_AUDIT_LOG'
    """)
    indexes = cursor.fetchall()
    for idx_name, partitioned in indexes:
        result["indexes"].append({"name": idx_name, "partitioned": partitioned})
        if partitioned == 'YES':
            result["local_index_count"] += 1
            
    # Check specific columns indexed (optional but good for debugging)
    cursor.execute("""
        SELECT i.index_name, c.column_name 
        FROM user_ind_columns c
        JOIN user_indexes i ON c.index_name = i.index_name
        WHERE i.table_name = 'EMPLOYEE_AUDIT_LOG'
    """)
    # (Just storing for manual debug if needed, logic is above)

    cursor.close()
    conn.close()

except Exception as e:
    result["db_error"] = str(e)

# 4. Check summary file
file_path = "/home/ga/Desktop/partition_summary.txt"
if os.path.exists(file_path):
    result["summary_file_exists"] = True
    try:
        with open(file_path, 'r') as f:
            result["summary_file_content"] = f.read(1000) # Read first 1kb
    except:
        pass

# Save to JSON
with open("/tmp/partition_audit_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

# Validate JSON
if [ -f "/tmp/partition_audit_result.json" ]; then
    echo "Export successful."
else
    echo "ERROR: Export failed, JSON not created."
    exit 1
fi