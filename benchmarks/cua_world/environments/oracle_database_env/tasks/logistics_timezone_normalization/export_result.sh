#!/bin/bash
# Export script for logistics_timezone_normalization
# Queries the user's view to verify correctness of timezone logic

set -e
echo "=== Exporting Logistics Result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check CSV Report
CSV_PATH="/home/ga/Desktop/long_haul_report.csv"
CSV_EXISTS="false"
CSV_CONTENT=""
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_CONTENT=$(head -n 5 "$CSV_PATH")
fi

# 3. Query the user's view (V_FLIGHT_ANALYSIS)
# We fetch specific columns for the test flights to verify calculations
# formatting timestamps as UTC strings for easy Python parsing
echo "Querying view V_FLIGHT_ANALYSIS..."

VIEW_DATA=$(python3 << 'PYEOF'
import oracledb
import json
import os

result = {
    "view_exists": False,
    "rows": [],
    "columns": [],
    "error": None
}

try:
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # Check view existence
    cursor.execute("SELECT count(*) FROM user_views WHERE view_name = 'V_FLIGHT_ANALYSIS'")
    if cursor.fetchone()[0] == 0:
        result["error"] = "View V_FLIGHT_ANALYSIS not found"
    else:
        result["view_exists"] = True
        
        # Get column names
        cursor.execute("SELECT column_name, data_type FROM user_tab_cols WHERE table_name = 'V_FLIGHT_ANALYSIS'")
        result["columns"] = [{"name": r[0], "type": r[1]} for r in cursor.fetchall()]

        # Query data for test flights
        # We assume the user named columns as requested: FLIGHT_ID, DEPART_UTC, ARRIVE_UTC, DURATION_MINUTES
        # We use a permissive query in case of slight naming variations, but task spec was strict.
        
        sql = """
            SELECT flight_id, 
                   TO_CHAR(depart_utc, 'YYYY-MM-DD HH24:MI:SS') as dep,
                   TO_CHAR(arrive_utc, 'YYYY-MM-DD HH24:MI:SS') as arr,
                   duration_minutes
            FROM v_flight_analysis
            WHERE flight_id IN (100, 200, 800, 900)
            ORDER BY flight_id
        """
        cursor.execute(sql)
        for row in cursor.fetchall():
            result["rows"].append({
                "flight_id": row[0],
                "depart_utc": row[1],
                "arrive_utc": row[2],
                "duration": row[3]
            })

    cursor.close()
    conn.close()

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF
)

# 4. Construct JSON Result
cat > /tmp/task_result.json << EOF
{
    "csv_exists": $CSV_EXISTS,
    "csv_content_sample": "$(echo "$CSV_CONTENT" | sed 's/"/\\"/g')",
    "view_data": $VIEW_DATA,
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="