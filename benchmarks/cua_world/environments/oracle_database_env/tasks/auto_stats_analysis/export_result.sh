#!/bin/bash
# Export script for Auto Stats Analysis
# Extracts the view definition, statistics, and outlier table content for verification

set -e

echo "=== Exporting Task Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Capture timestamps
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# Use Python to reliably extract data from Oracle to JSON
python3 << 'PYEOF'
import oracledb
import json
import os
import sys

# Connect to Oracle
try:
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()
except Exception as e:
    print(f"DB Connection Error: {e}")
    sys.exit(1)

result = {
    "stats_model_view_exists": False,
    "stats_model_data": {},
    "efficient_outliers_table_exists": False,
    "efficient_outliers_columns": [],
    "efficient_outliers_data": [],
    "errors": []
}

# 1. Check STATS_MODEL View
try:
    cursor.execute("SELECT count(*) FROM user_views WHERE view_name = 'STATS_MODEL'")
    if cursor.fetchone()[0] > 0:
        result["stats_model_view_exists"] = True
        
        # Get data from view
        try:
            cursor.execute("SELECT * FROM stats_model")
            columns = [col[0] for col in cursor.description]
            row = cursor.fetchone()
            if row:
                result["stats_model_data"] = dict(zip(columns, row))
        except Exception as e:
            result["errors"].append(f"Error querying STATS_MODEL: {str(e)}")
    else:
        # Check if they made a table instead of a view (common mistake, still partial credit maybe?)
        cursor.execute("SELECT count(*) FROM user_tables WHERE table_name = 'STATS_MODEL'")
        if cursor.fetchone()[0] > 0:
             result["errors"].append("STATS_MODEL is a TABLE, expected VIEW")
except Exception as e:
    result["errors"].append(f"Error checking STATS_MODEL: {str(e)}")

# 2. Check EFFICIENT_OUTLIERS Table
try:
    cursor.execute("SELECT count(*) FROM user_tables WHERE table_name = 'EFFICIENT_OUTLIERS'")
    if cursor.fetchone()[0] > 0:
        result["efficient_outliers_table_exists"] = True
        
        # Get columns
        cursor.execute("SELECT column_name FROM user_tab_columns WHERE table_name = 'EFFICIENT_OUTLIERS'")
        result["efficient_outliers_columns"] = [row[0] for row in cursor.fetchall()]
        
        # Get data (limit to top 20 to avoid huge json)
        try:
            # We want to verify the order and the data
            cursor.execute("""
                SELECT make, model, curb_weight_lbs, combined_mpg, 
                       predicted_mpg, diff_from_model 
                FROM efficient_outliers 
                ORDER BY diff_from_model DESC
            """)
            outlier_cols = [col[0] for col in cursor.description]
            rows = cursor.fetchall()
            
            # Convert to list of dicts
            data = []
            for r in rows:
                item = {}
                for i, val in enumerate(r):
                    # Handle decimals for JSON serialization
                    if val is not None and isinstance(val, float):
                        item[outlier_cols[i]] = float(val)
                    else:
                        item[outlier_cols[i]] = val
                data.append(item)
            result["efficient_outliers_data"] = data
            
        except Exception as e:
             result["errors"].append(f"Error querying EFFICIENT_OUTLIERS data: {str(e)}")
except Exception as e:
    result["errors"].append(f"Error checking EFFICIENT_OUTLIERS: {str(e)}")

# 3. Get Ground Truth Data (Raw) for Verifier to calculate independently if needed
# (Or we just trust the verifier's hardcoded logic since data is static in setup)
# We will just export the raw data so verifier can re-calculate regression
try:
    cursor.execute("SELECT curb_weight_lbs, combined_mpg FROM vehicle_tests")
    raw_data = cursor.fetchall()
    result["raw_data_points"] = [{"weight": r[0], "mpg": r[1]} for r in raw_data]
except Exception as e:
    result["errors"].append(f"Error fetching raw data: {str(e)}")

cursor.close()
conn.close()

# Save to JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="