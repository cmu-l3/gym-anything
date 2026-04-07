#!/bin/bash
# Export script for recursive_demand_forecasting
# Exports the agent's DEMAND_FORECAST table and the original WEEKLY_SALES for verification.

set -e
echo "=== Exporting Forecast Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Use Python with oracledb to export data reliably to JSON
# We export BOTH the agent's table and the source table to ensure we verify against the actual environment state
python3 << 'PYEOF'
import oracledb
import json
import os
import datetime

result = {
    "source_data": [],
    "agent_data": [],
    "table_exists": False,
    "columns": [],
    "error": None,
    "export_timestamp": datetime.datetime.now().isoformat()
}

try:
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # 1. Fetch Source Data (Truth Basis)
    cursor.execute("SELECT product_name, week_num, qty_sold FROM weekly_sales ORDER BY product_name, week_num")
    for row in cursor.fetchall():
        result["source_data"].append({
            "product": row[0],
            "week": row[1],
            "qty": float(row[2])
        })

    # 2. Check if Agent's Table Exists
    cursor.execute("SELECT table_name FROM user_tables WHERE table_name = 'DEMAND_FORECAST'")
    if cursor.fetchone():
        result["table_exists"] = True
        
        # Get columns to verify structure
        cursor.execute("SELECT column_name, data_type FROM user_tab_cols WHERE table_name = 'DEMAND_FORECAST'")
        result["columns"] = [{"name": r[0], "type": r[1]} for r in cursor.fetchall()]

        # Fetch Agent's Data
        # We try to be flexible with column names if they exist, but generally expect specific structure
        # If columns match expectations roughly, we query.
        try:
            cursor.execute("SELECT product_name, week_num, qty, data_type FROM demand_forecast ORDER BY product_name, week_num")
            for row in cursor.fetchall():
                result["agent_data"].append({
                    "product": row[0],
                    "week": row[1],
                    "qty": float(row[2]) if row[2] is not None else 0.0,
                    "type": row[3]
                })
        except Exception as query_err:
            result["error"] = f"Table exists but query failed (wrong columns?): {str(query_err)}"
    else:
        result["error"] = "Table DEMAND_FORECAST not found"

    cursor.close()
    conn.close()

except Exception as e:
    result["error"] = f"Database connection/export error: {str(e)}"

with open("/tmp/forecast_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export complete.")
PYEOF

# Set permissions so the host can read it via copy_from_env
chmod 644 /tmp/forecast_result.json

echo "=== Export Complete ==="