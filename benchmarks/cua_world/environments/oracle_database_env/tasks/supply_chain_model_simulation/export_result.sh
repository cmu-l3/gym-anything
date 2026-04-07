#!/bin/bash
# Export script for Supply Chain Simulation
# Captures the view definition (to check for MODEL clause) and the view output (to check logic)

set -e
echo "=== Exporting Supply Chain Task Results ==="

source /workspace/scripts/task_utils.sh

# Capture screenshot
take_screenshot /tmp/task_end_screenshot.png

# Paths
OUTPUT_CSV="/home/ga/Desktop/forecast_results.csv"

# Check CSV file existence/properties
CSV_EXISTS="false"
CSV_SIZE=0
if [ -f "$OUTPUT_CSV" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c %s "$OUTPUT_CSV")
fi

# Run python script to extract database state deeply
python3 << 'PYEOF'
import oracledb
import json
import os

result = {
    "view_exists": False,
    "view_text": "",
    "uses_model_clause": False,
    "columns": [],
    "row_count": 0,
    "logic_check_p101": [],
    "db_error": None
}

try:
    conn = oracledb.connect(user="logistics", password="logistics123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # 1. Check View Definition
    cursor.execute("""
        SELECT text 
        FROM user_views 
        WHERE view_name = 'INVENTORY_FORECAST'
    """)
    row = cursor.fetchone()
    if row:
        result["view_exists"] = True
        view_text = str(row[0]).upper()
        result["view_text"] = view_text
        if "MODEL" in view_text:
            result["uses_model_clause"] = True

    # 2. Check Columns
    if result["view_exists"]:
        cursor.execute("""
            SELECT column_name 
            FROM user_tab_columns 
            WHERE table_name = 'INVENTORY_FORECAST'
        """)
        result["columns"] = [r[0] for r in cursor.fetchall()]

        # 3. Check Data Content (Specific Logic Check for Product 101)
        # We need to verify the sequential calculation
        cursor.execute("""
            SELECT week_no, opening_stock, arrivals, demand_qty, closing_stock, order_qty 
            FROM inventory_forecast 
            WHERE product_id = 101 
            ORDER BY week_no
        """)
        rows = cursor.fetchall()
        result["row_count"] = len(rows)
        # Store first 3 weeks for verification
        result["logic_check_p101"] = [
            {
                "week": r[0],
                "open": float(r[1]) if r[1] is not None else 0,
                "arr": float(r[2]) if r[2] is not None else 0,
                "dem": float(r[3]) if r[3] is not None else 0,
                "close": float(r[4]) if r[4] is not None else 0,
                "order": float(r[5]) if r[5] is not None else 0
            } for r in rows[:3]
        ]
        
    cursor.close()
    conn.close()

except Exception as e:
    result["db_error"] = str(e)

# Save DB result
with open("/tmp/db_verification.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

# Combine info into final result
cat > /tmp/supply_chain_result.json << EOJSON
{
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    "db_verification": $(cat /tmp/db_verification.json)
}
EOJSON

echo "Export complete. Results saved to /tmp/supply_chain_result.json"