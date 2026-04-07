#!/bin/bash
set -e

echo "=== Exporting Marketing ROI Result ==="

source /workspace/scripts/task_utils.sh

# Record Task End
date +%s > /tmp/task_end_time

# Take Final Screenshot (Evidence of Work)
take_screenshot /tmp/task_final.png

# Query the agent's view and export to JSON
# We use Python/oracledb to handle potential NULLs or schema errors gracefully
python3 << 'PYEOF'
import oracledb
import json
import os

result = {
    "view_exists": False,
    "rows": [],
    "error": None
}

try:
    # Connect
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # Check view existence
    cursor.execute("SELECT count(*) FROM user_views WHERE view_name = 'CAMPAIGN_ROI_ANALYSIS'")
    if cursor.fetchone()[0] > 0:
        result["view_exists"] = True
        
        # Query Data
        # Ensure we get columns in expected order or by name
        try:
            cursor.execute("""
                SELECT region_id, total_spend, total_sales, 
                       corr_lag0, slope_lag0, 
                       corr_lag1, slope_lag1, 
                       best_strategy
                FROM CAMPAIGN_ROI_ANALYSIS
                ORDER BY region_id
            """)
            
            columns = [col[0].lower() for col in cursor.description]
            for row in cursor.fetchall():
                row_dict = {}
                for i, val in enumerate(row):
                    row_dict[columns[i]] = float(val) if isinstance(val, (int, float)) and val is not None else val
                result["rows"].append(row_dict)
                
        except Exception as q_err:
            result["error"] = f"Query Error: {str(q_err)}"
    else:
        result["error"] = "View CAMPAIGN_ROI_ANALYSIS not found."

except Exception as e:
    result["error"] = f"Connection Error: {str(e)}"

# Save to temp file
with open('/tmp/agent_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Export finished.")
PYEOF

# Secure copy to readable location
cp /tmp/agent_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

cat /tmp/task_result.json