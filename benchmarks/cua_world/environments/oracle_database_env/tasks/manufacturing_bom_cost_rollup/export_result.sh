#!/bin/bash
# Export results for manufacturing_bom_cost_rollup task

set -e

echo "=== Exporting Manufacturing BOM Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# --- Export Logic ---
# We need to:
# 1. Check if the view exists and is valid.
# 2. Query the view to get the calculated costs for key items (Server X1, CPU Module).
# 3. Check if the CSV file exists and read its content.

python3 << 'PYEOF'
import oracledb
import json
import os
import csv
import time

result = {
    "view_exists": False,
    "view_status": "MISSING",
    "calculated_costs": {},
    "csv_exists": False,
    "csv_content": [],
    "csv_created_during_task": False,
    "db_error": None
}

# 1. DB Checks
try:
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # Check View Existence
    cursor.execute("SELECT status FROM user_objects WHERE object_name = 'ASSEMBLY_COST_ANALYSIS' AND object_type = 'VIEW'")
    row = cursor.fetchone()
    if row:
        result["view_exists"] = True
        result["view_status"] = row[0]

        # Query View for Key Items if valid
        if row[0] == 'VALID':
            try:
                # Get cost for Server X1 (ID 30) and CPU Module (ID 20)
                # We query by name to be robust against ID assumptions, though IDs are fixed in setup
                cursor.execute("""
                    SELECT part_name, total_unit_cost 
                    FROM assembly_cost_analysis 
                    WHERE part_name IN ('Server X1', 'CPU Module', 'RAM Stick', 'Case Frame')
                """)
                rows = cursor.fetchall()
                for r in rows:
                    # Convert Decimal to float for JSON serialization
                    result["calculated_costs"][r[0]] = float(r[1]) if r[1] is not None else 0.0
            except Exception as e:
                result["db_error"] = f"Error querying view: {str(e)}"
    
    cursor.close()
    conn.close()

except Exception as e:
    result["db_error"] = str(e)

# 2. CSV Checks
csv_path = "/home/ga/Desktop/top_expensive_products.csv"
if os.path.exists(csv_path):
    result["csv_exists"] = True
    
    # Check timestamp
    try:
        task_start = 0
        if os.path.exists("/tmp/task_start_time"):
            with open("/tmp/task_start_time", "r") as f:
                task_start = int(f.read().strip())
        
        file_mtime = os.path.getmtime(csv_path)
        if file_mtime > task_start:
            result["csv_created_during_task"] = True
    except:
        pass

    # Read content
    try:
        with open(csv_path, 'r') as f:
            reader = csv.reader(f)
            # Read first 10 rows
            rows = []
            for i, row in enumerate(reader):
                if i < 10:
                    rows.append(row)
            result["csv_content"] = rows
    except Exception as e:
        result["csv_read_error"] = str(e)

# Save to JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export complete.")
PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="