#!/bin/bash
# Export results for partitioned_archival_strategy task

set -e

echo "=== Exporting Partitioned Archival Strategy Results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/archive_strategy_final_screenshot.png

echo "[1/3] Reading baseline..."
JH_BASELINE=$(cat /tmp/initial_job_history_count_archive 2>/dev/null || echo "10")
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

echo "[2/3] Querying Oracle objects and partition data..."
python3 << PYEOF
import oracledb
import json
import os

result = {
    "job_history_baseline": int("${JH_BASELINE}"),
    "task_start_timestamp": int("${TASK_START}"),
    "archive_table_exists": False,
    "archive_table_partitioned": False,
    "archive_partition_count": 0,
    "archive_partitions": [],
    "archive_total_rows": 0,
    "bitmap_indexes": [],
    "mv_dept_turnover_exists": False,
    "mv_dept_turnover_status": "NOT FOUND",
    "mv_dept_turnover_rows": 0,
    "mv_sample_rows": [],
    "archive_analysis_file_exists": False,
    "archive_analysis_file_size": 0,
    "archive_analysis_preview": ""
}

try:
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # Check archive table existence and partitioning
    cursor.execute("""
        SELECT table_name, partitioned
        FROM user_tables
        WHERE table_name = 'EMPLOYEE_HISTORY_ARCHIVE'
    """)
    row = cursor.fetchone()
    if row:
        result["archive_table_exists"] = True
        result["archive_table_partitioned"] = (row[1] == "YES")

    if result["archive_table_exists"]:
        # Count partitions
        cursor.execute("""
            SELECT partition_name, high_value, num_rows, last_analyzed
            FROM user_tab_partitions
            WHERE table_name = 'EMPLOYEE_HISTORY_ARCHIVE'
            ORDER BY partition_position
        """)
        partitions = []
        for row in cursor.fetchall():
            partitions.append({
                "name": row[0],
                "high_value": str(row[1])[:100] if row[1] else None,
                "num_rows": row[2]
            })
        result["archive_partitions"] = partitions
        result["archive_partition_count"] = len(partitions)

        # Total row count
        try:
            cursor.execute("SELECT COUNT(*) FROM employee_history_archive")
            result["archive_total_rows"] = cursor.fetchone()[0]
        except Exception as e:
            result["archive_total_rows_error"] = str(e)[:200]

        # Check partition row counts directly (analyze if needed)
        try:
            cursor.execute("""
                SELECT partition_name, COUNT(*)
                FROM employee_history_archive
                PARTITION BY (end_date)
                GROUP BY partition_name
            """)
        except Exception:
            pass  # Not critical

    # Check bitmap indexes on archive table
    cursor.execute("""
        SELECT i.index_name, i.index_type, ic.column_name
        FROM user_indexes i
        JOIN user_ind_columns ic ON i.index_name = ic.index_name
        WHERE i.table_name = 'EMPLOYEE_HISTORY_ARCHIVE'
          AND i.index_type = 'BITMAP'
    """)
    bitmap_indexes = []
    for row in cursor.fetchall():
        bitmap_indexes.append({
            "index_name": row[0],
            "column": row[2]
        })
    result["bitmap_indexes"] = bitmap_indexes

    # Check materialized view
    cursor.execute("""
        SELECT mview_name, refresh_mode, refresh_method,
               compile_state, last_refresh_date
        FROM user_mviews
        WHERE mview_name = 'MV_DEPT_TURNOVER'
    """)
    row = cursor.fetchone()
    if row:
        result["mv_dept_turnover_exists"] = True
        result["mv_dept_turnover_status"] = row[3] if row[3] else "UNKNOWN"

        # Row count in MV
        try:
            cursor.execute("SELECT COUNT(*) FROM mv_dept_turnover")
            result["mv_dept_turnover_rows"] = cursor.fetchone()[0]

            # Sample rows
            cursor.execute("SELECT * FROM mv_dept_turnover WHERE ROWNUM <= 5")
            cols = [desc[0] for desc in cursor.description]
            rows = cursor.fetchall()
            result["mv_sample_rows"] = [dict(zip(cols, [str(v) for v in row])) for row in rows]
        except Exception as e:
            result["mv_query_error"] = str(e)[:200]

    cursor.close()
    conn.close()

except Exception as e:
    result["db_error"] = str(e)[:500]

# Check archive_analysis.txt
txt_path = "/home/ga/Desktop/archive_analysis.txt"
if os.path.exists(txt_path):
    result["archive_analysis_file_exists"] = True
    result["archive_analysis_file_size"] = os.path.getsize(txt_path)
    try:
        with open(txt_path, "r") as f:
            content = f.read()
        result["archive_analysis_preview"] = content[:800]
        result["archive_analysis_line_count"] = len([l for l in content.splitlines() if l.strip()])
    except Exception as e:
        result["archive_analysis_preview"] = f"READ ERROR: {e}"

with open("/tmp/partitioned_archival_strategy_result.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

print(json.dumps({
    "archive_table_exists": result["archive_table_exists"],
    "partitioned": result["archive_table_partitioned"],
    "partitions": result["archive_partition_count"],
    "archive_rows": result["archive_total_rows"],
    "bitmap_indexes": len(result["bitmap_indexes"]),
    "mv_exists": result["mv_dept_turnover_exists"],
    "file_exists": result["archive_analysis_file_exists"]
}, indent=2))
PYEOF

echo "[3/3] Validating result JSON..."
python3 -m json.tool /tmp/partitioned_archival_strategy_result.json > /dev/null && echo "  Result JSON valid"

echo "=== Export Complete ==="
echo "  Results saved to: /tmp/partitioned_archival_strategy_result.json"
