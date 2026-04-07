#!/bin/bash
# Export results for Partition Exchange task

set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting Results ==="

take_screenshot /tmp/task_end.png

# Capture timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_STAGING_COUNT=$(cat /tmp/initial_staging_count.txt 2>/dev/null || echo "0")

# Run python verification script to check DB state
python3 << PYEOF
import oracledb
import json
import os

result = {
    "task_start": ${TASK_START},
    "initial_staging_count": int("${INITIAL_STAGING_COUNT}"),
    "current_staging_count": -1,
    "fact_partition_count": -1,
    "global_index_status": "UNKNOWN",
    "local_index_status": "UNKNOWN",
    "staging_index_created": False,
    "db_error": None
}

try:
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # 1. Check Row Counts
    cursor.execute("SELECT COUNT(*) FROM sales_staging_dec11")
    result["current_staging_count"] = cursor.fetchone()[0]

    cursor.execute("SELECT COUNT(*) FROM sales_fact PARTITION (p_2011_12)")
    result["fact_partition_count"] = cursor.fetchone()[0]

    # 2. Check Global Index Status
    cursor.execute("SELECT status FROM user_indexes WHERE index_name = 'IDX_SALES_CUSTOMER'")
    row = cursor.fetchone()
    if row:
        result["global_index_status"] = row[0]
    
    # 3. Check Local Index Status (All partitions should be USABLE)
    cursor.execute("SELECT status FROM user_ind_partitions WHERE index_name = 'IDX_SALES_INVOICE' AND status = 'UNUSABLE'")
    unusable_count = len(cursor.fetchall())
    if unusable_count == 0:
        result["local_index_status"] = "VALID"
    else:
        result["local_index_status"] = "UNUSABLE_PARTITIONS_FOUND"

    # 4. Check if Staging Table has indexes (Evidence of correct prep)
    # The user should have created indexes on the staging table before exchange
    # However, if they swapped, the indexes might now be on the staging table (if they came from the partition) 
    # OR if they dropped them. 
    # Actually, EXCHANGE PARTITION swaps indexes too. 
    # If Fact had local index, Staging must have matching index. 
    # After swap, Staging gets the empty partition's "local index" segment (which is empty).
    # So Staging SHOULD have an index on invoice_no after swap.
    cursor.execute("SELECT COUNT(*) FROM user_indexes WHERE table_name = 'SALES_STAGING_DEC11'")
    idx_count = cursor.fetchone()[0]
    result["staging_index_created"] = (idx_count > 0)

    cursor.close()
    conn.close()

except Exception as e:
    result["db_error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json
echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json