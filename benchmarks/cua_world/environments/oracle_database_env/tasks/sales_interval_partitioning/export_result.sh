#!/bin/bash
# Export script for Sales Interval Partitioning task
# Queries Oracle metadata views to verify partitioning strategy and data loading

set -e

echo "=== Exporting Sales Partitioning Results ==="

source /workspace/scripts/task_utils.sh

# Record final screenshot
take_screenshot /tmp/task_final.png

# Use Python to extract rich metadata structure from Oracle
python3 << 'PYEOF'
import oracledb
import json
import os
import sys

# Default result structure
result = {
    "table_exists": False,
    "partitioning_type": None,
    "subpartitioning_type": None,
    "interval_clause": None,
    "row_count": 0,
    "subpartition_names": [],
    "subpartition_high_values": [],
    "local_indexes": [],
    "future_record_found": False,
    "partition_count": 0,
    "error": None
}

try:
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # 1. Check Table Structure & Partitioning Strategy
    print("Checking partitioning strategy...")
    cursor.execute("""
        SELECT partitioning_type, subpartitioning_type, interval
        FROM user_part_tables
        WHERE table_name = 'GLOBAL_SALES'
    """)
    row = cursor.fetchone()
    if row:
        result["table_exists"] = True
        result["partitioning_type"] = row[0]       # Expected: RANGE (Interval shows as Range)
        result["subpartitioning_type"] = row[1]    # Expected: LIST
        result["interval_clause"] = str(row[2]) if row[2] else None  # Expected: NOT NULL (e.g., NUMTOYMINTERVAL(1,'MONTH'))

    if result["table_exists"]:
        # 2. Check Row Count
        cursor.execute("SELECT COUNT(*) FROM global_sales")
        result["row_count"] = cursor.fetchone()[0]

        # 3. Check for the specific future record (2028 automation test)
        # Note: We check if it exists in the table. The fact that it exists implies
        # the interval partition was created if the table is partitioned.
        cursor.execute("""
            SELECT COUNT(*) FROM global_sales 
            WHERE sale_date = TO_DATE('2028-01-15', 'YYYY-MM-DD') 
            AND amount = 999.99
        """)
        if cursor.fetchone()[0] > 0:
            result["future_record_found"] = True

        # 4. Check Subpartition Definitions
        # We look for the High Values to confirm NA, EU, AS, SA are defined
        # Note: High_value is a LONG column in Oracle, tricky to read sometimes, 
        # but for LIST it's usually short string.
        # Alternatively, we can check the subpartition count and sample names.
        cursor.execute("""
            SELECT subpartition_name, high_value 
            FROM user_tab_subpartitions 
            WHERE table_name = 'GLOBAL_SALES'
            AND ROWNUM <= 20
        """)
        # We just grab a sample to verify structure exists
        rows = cursor.fetchall()
        result["subpartition_names"] = [r[0] for r in rows]
        # high_value is tough to parse directly in some drivers, capture string rep if possible
        result["subpartition_high_values"] = [str(r[1]) for r in rows]
        
        cursor.execute("SELECT COUNT(*) FROM user_tab_partitions WHERE table_name = 'GLOBAL_SALES'")
        result["partition_count"] = cursor.fetchone()[0]

        # 5. Check Index Locality
        cursor.execute("""
            SELECT index_name, partitioning_type, locality
            FROM user_part_indexes
            WHERE table_name = 'GLOBAL_SALES'
        """)
        idx_rows = cursor.fetchall()
        for idx in idx_rows:
            result["local_indexes"].append({
                "name": idx[0],
                "type": idx[1],
                "locality": idx[2] # Expected: LOCAL
            })

except Exception as e:
    result["error"] = str(e)
    print(f"Database Error: {e}")
finally:
    if 'conn' in locals(): conn.close()

# Write result to file
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export complete.")
PYEOF

# Set permissions so verifier can read it
chmod 644 /tmp/task_result.json

# Check if agent created the structure text file
if [ -f "/home/ga/Desktop/partition_structure.txt" ]; then
    echo "Partition structure file found."
fi

echo "=== Export Complete ==="