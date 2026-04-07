#!/bin/bash
# Export script for financial_grouping_sets_report
# Exports view definition and query results for verification

set -e
echo "=== Exporting Financial Report Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# We use Python to handle the complex validation logic (checking DDL and values)
# and export a JSON result file.

python3 << 'PYEOF'
import oracledb
import json
import os
import re

result = {
    "view_exists": False,
    "view_ddl": "",
    "ddl_uses_union": False,
    "ddl_uses_grouping": False,
    "column_names": [],
    "row_count": 0,
    "grand_total_match": False,
    "region_subtotal_match": False,
    "category_subtotal_match": False,
    "labels_correct": False,
    "actual_grand_total": 0,
    "view_grand_total": 0,
    "db_error": ""
}

try:
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # 1. Check View Existence and DDL
    cursor.execute("""
        SELECT text FROM user_views 
        WHERE view_name = 'REVENUE_SUMMARY_VIEW'
    """)
    row = cursor.fetchone()
    if row:
        result["view_exists"] = True
        # Handle CLOB or string
        ddl = str(row[0]).upper()
        result["view_ddl"] = ddl
        
        if "UNION" in ddl:
            result["ddl_uses_union"] = True
        
        if any(x in ddl for x in ["GROUPING SETS", "ROLLUP", "CUBE"]):
            result["ddl_uses_grouping"] = True
            
        # Check column names
        cursor.execute("""
            SELECT column_name FROM user_tab_columns 
            WHERE table_name = 'REVENUE_SUMMARY_VIEW'
            ORDER BY column_id
        """)
        result["column_names"] = [r[0] for r in cursor.fetchall()]
        
        # 2. Get Ground Truths
        cursor.execute("SELECT SUM(amount) FROM sales_transactions")
        gt_grand = cursor.fetchone()[0] or 0
        result["actual_grand_total"] = float(gt_grand)
        
        # 3. Validate View Content
        
        # Check Row Count
        # Expected: (4 regions * 4 cats) + 4 regions + 4 cats + 1 grand = 16 + 4 + 4 + 1 = 25
        cursor.execute("SELECT COUNT(*) FROM revenue_summary_view")
        result["row_count"] = cursor.fetchone()[0]
        
        # Check Grand Total Row
        # We look for the row that should be 'All Regions', 'All Categories'
        # But we verify loosely first just in case labels are slightly off, 
        # then strictly for the "labels_correct" check.
        
        cursor.execute("""
            SELECT total_revenue FROM revenue_summary_view 
            WHERE report_region = 'All Regions' AND report_category = 'All Categories'
        """)
        row = cursor.fetchone()
        if row:
            result["view_grand_total"] = float(row[0])
            result["labels_correct"] = True
            if abs(result["view_grand_total"] - result["actual_grand_total"]) < 0.1:
                result["grand_total_match"] = True
        
        # Check a specific region subtotal (e.g., 'North')
        cursor.execute("SELECT SUM(amount) FROM sales_transactions WHERE region='North'")
        north_actual = float(cursor.fetchone()[0] or 0)
        
        cursor.execute("""
            SELECT total_revenue FROM revenue_summary_view
            WHERE report_region = 'North' 
            AND (report_category = 'All Categories' OR report_category IS NULL)
        """)
        row = cursor.fetchone()
        if row and abs(float(row[0]) - north_actual) < 0.1:
            result["region_subtotal_match"] = True
            
        # Check a specific category subtotal (e.g., 'Electronics')
        cursor.execute("SELECT SUM(amount) FROM sales_transactions WHERE category='Electronics'")
        elec_actual = float(cursor.fetchone()[0] or 0)
        
        cursor.execute("""
            SELECT total_revenue FROM revenue_summary_view
            WHERE (report_region = 'All Regions' OR report_region IS NULL)
            AND report_category = 'Electronics'
        """)
        row = cursor.fetchone()
        if row and abs(float(row[0]) - elec_actual) < 0.1:
            result["category_subtotal_match"] = True

except Exception as e:
    result["db_error"] = str(e)

# Save result
with open("/tmp/grouping_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

# Fix permissions
chmod 666 /tmp/grouping_result.json 2>/dev/null || true

echo "=== Export Complete ==="