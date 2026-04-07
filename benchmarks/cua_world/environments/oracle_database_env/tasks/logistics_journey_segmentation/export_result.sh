#!/bin/bash
# Export script for logistics_journey_segmentation
# Verifies the view structure, data content, and CSV export

set -e
echo "=== Exporting Logistics Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Path to expected CSV
CSV_PATH="/home/ga/Desktop/journey_report.csv"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Python script to validate database state and file existence
python3 << 'PYEOF'
import oracledb
import json
import os
import csv
from datetime import datetime

result = {
    "view_exists": False,
    "view_columns": [],
    "row_count": 0,
    "segments_101": 0,  # Expected 4
    "segments_102": 0,  # Expected 1
    "segments_103": 0,  # Expected 5
    "correct_logic_aba": False, # Checks if 101 has distinct transit segments
    "csv_exists": False,
    "csv_rows": 0,
    "csv_created_during_task": False,
    "error": None
}

try:
    # 1. Database Checks
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # Check View Existence
    cursor.execute("SELECT view_name FROM user_views WHERE view_name = 'JOURNEY_SEGMENTS'")
    if cursor.fetchone():
        result["view_exists"] = True
        
        # Check Columns
        cursor.execute("SELECT column_name FROM user_tab_cols WHERE table_name = 'JOURNEY_SEGMENTS'")
        result["view_columns"] = [r[0] for r in cursor.fetchall()]

        # Check Data Content
        try:
            # Get all segments for analysis
            cursor.execute("SELECT container_id, status, start_time, end_time FROM journey_segments ORDER BY container_id, start_time")
            rows = cursor.fetchall()
            result["row_count"] = len(rows)

            # Analyze Container 101 (The A-B-A test)
            c101 = [r for r in rows if r[0] == 101]
            result["segments_101"] = len(c101)
            
            # Check for A-B-A pattern logic: Transit -> Customs -> Transit
            if len(c101) >= 3:
                s1, s2, s3 = c101[0][1], c101[1][1], c101[2][1]
                # If they grouped simply by status, s1 and s3 would be merged or adjacent without separation logic
                if s1 == 'IN_TRANSIT' and s2 == 'CUSTOMS' and s3 == 'IN_TRANSIT':
                    result["correct_logic_aba"] = True

            # Analyze Container 102 (The Static test)
            c102 = [r for r in rows if r[0] == 102]
            result["segments_102"] = len(c102)

            # Analyze Container 103 (The Erratic test)
            c103 = [r for r in rows if r[0] == 103]
            result["segments_103"] = len(c103)

        except Exception as e:
            result["error"] = f"Query Error: {str(e)}"
    
    cursor.close()
    conn.close()

    # 2. CSV File Checks
    csv_path = "/home/ga/Desktop/journey_report.csv"
    if os.path.exists(csv_path):
        result["csv_exists"] = True
        stat = os.stat(csv_path)
        if stat.st_mtime > int(os.environ.get("TASK_START", 0)):
            result["csv_created_during_task"] = True
        
        try:
            with open(csv_path, 'r') as f:
                # Count rows (excluding header)
                result["csv_rows"] = sum(1 for line in f) - 1
        except:
            pass

except Exception as e:
    result["error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json