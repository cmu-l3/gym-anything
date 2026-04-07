#!/bin/bash
# Export results for star_schema_warehouse task
# Inspects Oracle schema dictionary and output files

set -e

echo "=== Exporting Star Schema Warehouse Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Paths
REPORT_FILE="/home/ga/Desktop/warehouse_analysis.txt"
COUNTS_FILE="/home/ga/Desktop/warehouse_counts.txt"

# Check output files
REPORT_EXISTS="false"
REPORT_SIZE=0
REPORT_CONTENT_PREVIEW=""
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c%s "$REPORT_FILE")
    REPORT_CONTENT_PREVIEW=$(head -n 20 "$REPORT_FILE" | base64 -w 0)
fi

COUNTS_EXISTS="false"
COUNTS_CONTENT=""
if [ -f "$COUNTS_FILE" ]; then
    COUNTS_EXISTS="true"
    COUNTS_CONTENT=$(cat "$COUNTS_FILE" | base64 -w 0)
fi

# Run Python script to inspect Database Schema state
python3 << 'PYEOF'
import oracledb
import json
import os
import sys

result = {
    "tables": {},
    "constraints": [],
    "sample_data": {},
    "db_error": None
}

try:
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()
    
    target_tables = ['DIM_DEPARTMENT', 'DIM_JOB', 'DIM_EMPLOYEE', 'DIM_TIME', 'FACT_WORKFORCE']
    
    # Check tables, columns, and row counts
    for table in target_tables:
        table_info = {"exists": False, "columns": [], "row_count": 0}
        
        # Check existence and columns
        cursor.execute(f"SELECT column_name, data_type FROM user_tab_columns WHERE table_name = '{table}'")
        cols = cursor.fetchall()
        if cols:
            table_info["exists"] = True
            table_info["columns"] = [{"name": c[0], "type": c[1]} for c in cols]
            
            # Get row count
            cursor.execute(f"SELECT COUNT(*) FROM {table}")
            table_info["row_count"] = cursor.fetchone()[0]
            
            # Get sample row (for validation of content like computed columns)
            try:
                cursor.execute(f"SELECT * FROM {table} FETCH FIRST 1 ROWS ONLY")
                # We won't store the row itself to avoid serialization issues with dates/complex types easily
                # but we will check specific logic later or store string representation
                row = cursor.fetchone()
                if row:
                    table_info["has_data"] = True
            except:
                table_info["has_data"] = False
        
        result["tables"][table] = table_info

    # Check Foreign Keys on FACT_WORKFORCE
    cursor.execute("""
        SELECT constraint_name, r_constraint_name
        FROM user_constraints 
        WHERE table_name = 'FACT_WORKFORCE' AND constraint_type = 'R'
    """)
    fks = cursor.fetchall()
    result["constraints"] = [{"name": c[0], "refers_to_constraint": c[1]} for c in fks]
    
    # Specific Data Spot Checks
    
    # 1. Check DIM_JOB SALARY_RANGE computation
    if result["tables"].get("DIM_JOB", {}).get("exists"):
        try:
            cursor.execute("SELECT job_id, min_salary, max_salary, salary_range FROM dim_job WHERE rownum = 1")
            row = cursor.fetchone()
            if row:
                result["sample_data"]["dim_job"] = {
                    "min": row[1], "max": row[2], "range": row[3],
                    "valid_calc": (row[2] - row[1] == row[3]) if (row[1] is not None and row[2] is not None and row[3] is not None) else False
                }
        except Exception as e:
            result["sample_data"]["dim_job_error"] = str(e)
            
    # 2. Check DIM_DEPARTMENT denormalization (City/Region not null)
    if result["tables"].get("DIM_DEPARTMENT", {}).get("exists"):
        try:
            cursor.execute("SELECT COUNT(*) FROM dim_department WHERE city IS NOT NULL AND region_name IS NOT NULL")
            result["sample_data"]["dim_dept_valid_rows"] = cursor.fetchone()[0]
        except:
            pass
            
    # 3. Check FACT_WORKFORCE salary match
    if result["tables"].get("FACT_WORKFORCE", {}).get("exists"):
        try:
            # Join back to source to verify data accuracy for a sample employee
            cursor.execute("""
                SELECT f.salary, e.salary 
                FROM fact_workforce f 
                JOIN dim_employee d ON f.employee_key = d.employee_key
                JOIN employees e ON d.employee_id = e.employee_id
                WHERE rownum = 1
            """)
            row = cursor.fetchone()
            if row:
                result["sample_data"]["fact_salary_match"] = (row[0] == row[1])
        except Exception as e:
            result["sample_data"]["fact_error"] = str(e)

    cursor.close()
    conn.close()

except Exception as e:
    result["db_error"] = str(e)

# Save DB result
with open("/tmp/db_schema_state.json", "w") as f:
    json.dump(result, f, indent=2, default=str)
PYEOF

# Combine info into final result
cat > /tmp/task_result.json << EOJSON
{
    "report_exists": $REPORT_EXISTS,
    "report_size": $REPORT_SIZE,
    "report_content_b64": "$REPORT_CONTENT_PREVIEW",
    "counts_exists": $COUNTS_EXISTS,
    "counts_content_b64": "$COUNTS_CONTENT",
    "db_state": $(cat /tmp/db_schema_state.json)
}
EOJSON

echo "Result saved to /tmp/task_result.json"