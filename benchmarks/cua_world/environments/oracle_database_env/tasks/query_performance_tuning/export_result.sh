#!/bin/bash
# Export results for query_performance_tuning task

set -e

echo "=== Exporting Query Performance Tuning Results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/query_perf_final_screenshot.png

echo "[1/3] Reading baseline data..."
INITIAL_INDEX_COUNT=$(cat /tmp/initial_index_count_perf 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

echo "[2/3] Querying current index and file state..."
python3 << PYEOF
import oracledb
import json
import os

result = {
    "initial_index_count": int("${INITIAL_INDEX_COUNT}"),
    "task_start_timestamp": int("${TASK_START}"),
    "current_indexes": [],
    "new_index_count": 0,
    "indexes_on_airports": [],
    "indexes_on_flight_routes": [],
    "optimized_queries_file_exists": False,
    "optimized_queries_file_size": 0,
    "optimized_queries_content": "",
    "query_count_in_file": 0,
    "airport_count": 0,
    "route_count": 0,
    "explain_plan_samples": {}
}

try:
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # Get all user-created indexes on our tables
    cursor.execute("""
        SELECT index_name, table_name, index_type, uniqueness,
               status, num_rows, last_analyzed
        FROM user_indexes
        WHERE table_name IN ('AIRPORTS', 'FLIGHT_ROUTES')
          AND index_type != 'LOB'
        ORDER BY table_name, index_name
    """)
    all_indexes = []
    for row in cursor.fetchall():
        idx = {
            "index_name": row[0],
            "table_name": row[1],
            "index_type": row[2],
            "uniqueness": row[3],
            "status": row[4],
            "num_rows": row[5]
        }
        all_indexes.append(idx)
        if row[1] == "AIRPORTS":
            result["indexes_on_airports"].append(row[0])
        else:
            result["indexes_on_flight_routes"].append(row[0])
    result["current_indexes"] = all_indexes
    result["new_index_count"] = len(all_indexes) - result["initial_index_count"]

    # Get indexed columns for each index
    cursor.execute("""
        SELECT i.index_name, i.table_name, ic.column_name, ic.column_position
        FROM user_indexes i
        JOIN user_ind_columns ic ON i.index_name = ic.index_name
        WHERE i.table_name IN ('AIRPORTS', 'FLIGHT_ROUTES')
          AND i.index_type != 'LOB'
        ORDER BY i.table_name, i.index_name, ic.column_position
    """)
    index_cols = {}
    for row in cursor.fetchall():
        key = row[0]
        if key not in index_cols:
            index_cols[key] = {"table": row[1], "columns": []}
        index_cols[key]["columns"].append(row[2])
    result["index_columns"] = index_cols

    # Record current counts
    cursor.execute("SELECT COUNT(*) FROM airports")
    result["airport_count"] = cursor.fetchone()[0]
    cursor.execute("SELECT COUNT(*) FROM flight_routes")
    result["route_count"] = cursor.fetchone()[0]

    # Test EXPLAIN PLAN for query 1 (country filter) to check index usage
    try:
        cursor.execute("EXPLAIN PLAN FOR SELECT airport_id, name, city, iata_code FROM airports WHERE country = 'United States'")
        cursor.execute("SELECT operation, options, object_name, cost FROM plan_table WHERE ROWNUM <= 5 ORDER BY id")
        plan_rows = [{"op": r[0], "options": r[1], "object": r[2], "cost": r[3]} for r in cursor.fetchall()]
        result["explain_plan_samples"]["q1_country_filter"] = plan_rows
        # Delete the plan
        cursor.execute("DELETE FROM plan_table")
        conn.commit()
    except Exception as e:
        result["explain_plan_samples"]["q1_error"] = str(e)[:200]

    cursor.close()
    conn.close()

except Exception as e:
    result["db_error"] = str(e)[:500]

# Check optimized_queries.sql file
opt_path = "/home/ga/Desktop/optimized_queries.sql"
if os.path.exists(opt_path):
    result["optimized_queries_file_exists"] = True
    result["optimized_queries_file_size"] = os.path.getsize(opt_path)
    try:
        with open(opt_path, "r") as f:
            content = f.read()
        result["optimized_queries_content"] = content[:3000]
        # Count semicolons as a proxy for query count
        import re
        statements = [s.strip() for s in content.split(";") if s.strip() and len(s.strip()) > 20]
        result["query_count_in_file"] = len(statements)
    except Exception as e:
        result["optimized_queries_content"] = f"READ ERROR: {e}"

# Save result
with open("/tmp/query_performance_tuning_result.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

print(json.dumps({
    "new_index_count": result["new_index_count"],
    "optimized_file_exists": result["optimized_queries_file_exists"],
    "query_count": result["query_count_in_file"]
}, indent=2))
PYEOF

echo "[3/3] Validating result..."
python3 -m json.tool /tmp/query_performance_tuning_result.json > /dev/null && echo "  Result JSON valid"

echo "=== Export Complete ==="
echo "  Results saved to: /tmp/query_performance_tuning_result.json"
