#!/bin/bash
# Export script for Inventory Gap Filling task
# Verifies the content of the view DAILY_INVENTORY_FULL

set -e
echo "=== Exporting Inventory Gap Filling Results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

# We use Python to run complex verification queries and export structured JSON
# This allows us to handle the logic validation cleanly
python3 << 'PYEOF'
import oracledb
import json
import os
import datetime

result = {
    "view_exists": False,
    "total_rows": 0,
    "distinct_products": 0,
    "distinct_dates": 0,
    "scenario_a_gap_fill": None,    # Prod 500 on Jan 05 (should be 10)
    "scenario_b_initial": None,     # Prod 501 on Jan 01 (should be 0)
    "scenario_c_multi_update": None, # Prod 502 on Jan 01 (should be 110)
    "error": None
}

try:
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # 1. Check View Existence
    try:
        cursor.execute("SELECT COUNT(*) FROM DAILY_INVENTORY_FULL")
        row = cursor.fetchone()
        if row:
            result["view_exists"] = True
            result["total_rows"] = row[0]
    except oracledb.DatabaseError as e:
        result["error"] = str(e)
    
    if result["view_exists"]:
        # 2. Check Dimensions
        cursor.execute("SELECT COUNT(DISTINCT PRODUCT_ID) FROM DAILY_INVENTORY_FULL")
        result["distinct_products"] = cursor.fetchone()[0]
        
        cursor.execute("SELECT COUNT(DISTINCT REPORT_DATE) FROM DAILY_INVENTORY_FULL")
        result["distinct_dates"] = cursor.fetchone()[0]
        
        # 3. Scenario A: Gap Fill (Product 500)
        # Change on Jan 1 is 10. Next change Jan 10.
        # Query Jan 05 -> Should be 10.
        cursor.execute("""
            SELECT STOCK_LEVEL FROM DAILY_INVENTORY_FULL 
            WHERE PRODUCT_ID = 500 AND REPORT_DATE = DATE '2026-01-05'
        """)
        row = cursor.fetchone()
        result["scenario_a_gap_fill"] = float(row[0]) if row and row[0] is not None else None
        
        # 4. Scenario B: Initial Zeros (Product 501)
        # First change Jan 15.
        # Query Jan 01 -> Should be 0 (or null if they failed NVL, but task asks for 0)
        cursor.execute("""
            SELECT STOCK_LEVEL FROM DAILY_INVENTORY_FULL 
            WHERE PRODUCT_ID = 501 AND REPORT_DATE = DATE '2026-01-01'
        """)
        row = cursor.fetchone()
        result["scenario_b_initial"] = float(row[0]) if row and row[0] is not None else None
        
        # 5. Scenario C: Multi-update (Product 502)
        # Jan 1 had two updates: 100 then 110.
        # Query Jan 01 -> Should be 110.
        cursor.execute("""
            SELECT STOCK_LEVEL FROM DAILY_INVENTORY_FULL 
            WHERE PRODUCT_ID = 502 AND REPORT_DATE = DATE '2026-01-01'
        """)
        row = cursor.fetchone()
        result["scenario_c_multi_update"] = float(row[0]) if row and row[0] is not None else None

    cursor.close()
    conn.close()

except Exception as e:
    result["error"] = str(e)

with open("/tmp/inventory_gap_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export JSON created.")
PYEOF

echo "=== Export Complete ==="