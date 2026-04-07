#!/bin/bash
# Export script for SQL Macros Fiscal Reporting task
# Validates database objects and report content

set -e
echo "=== Exporting SQL Macros Task Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Path to expected output
REPORT_PATH="/home/ga/Desktop/fiscal_impact_report.csv"

# Run Python script to validate DB objects and data
python3 << 'PYEOF'
import oracledb
import json
import os
import csv
import datetime

result = {
    "scalar_macro_exists": False,
    "scalar_macro_is_macro": False,
    "scalar_macro_logic_score": 0,
    "table_macro_exists": False,
    "table_macro_is_macro": False,
    "table_macro_logic_score": 0,
    "report_exists": False,
    "report_valid_format": False,
    "report_data_accuracy": 0.0,
    "db_error": None
}

try:
    # Connect to DB
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # 1. Check GET_FISCAL_YEAR (Scalar Macro)
    cursor.execute("""
        SELECT object_type FROM user_objects 
        WHERE object_name = 'GET_FISCAL_YEAR'
    """)
    row = cursor.fetchone()
    if row:
        result["scalar_macro_exists"] = True
        # Check if it is actually a macro (SQL_MACRO='SCALAR' in user_procedures/user_functions in 21c+)
        # Simpler check: SQL Macros appear as functions. We check property in user_procedures (requires 19c/21c view columns)
        # Or try to select from it.
        try:
             cursor.execute("SELECT sql_macro FROM user_procedures WHERE object_name = 'GET_FISCAL_YEAR'")
             macro_type = cursor.fetchone()
             if macro_type and macro_type[0] == 'SCALAR':
                 result["scalar_macro_is_macro"] = True
        except:
             # Fallback if column doesn't exist (unlikely in 21c) or other error
             pass

        # Test Logic: Check Sep 30 vs Oct 1
        # Case 1: 2024-09-30 -> 2024
        # Case 2: 2024-10-01 -> 2025
        try:
            cursor.execute("SELECT get_fiscal_year(TO_DATE('2024-09-30', 'YYYY-MM-DD')) FROM dual")
            fy_sep = cursor.fetchone()[0]
            cursor.execute("SELECT get_fiscal_year(TO_DATE('2024-10-01', 'YYYY-MM-DD')) FROM dual")
            fy_oct = cursor.fetchone()[0]
            
            if fy_sep == 2024 and fy_oct == 2025:
                result["scalar_macro_logic_score"] = 1.0
            elif fy_sep == 2024 or fy_oct == 2025:
                result["scalar_macro_logic_score"] = 0.5
        except Exception as e:
            print(f"Scalar logic test failed: {e}")

    # 2. Check GET_HIGH_IMPACT_SALES (Table Macro)
    cursor.execute("""
        SELECT object_type FROM user_objects 
        WHERE object_name = 'GET_HIGH_IMPACT_SALES'
    """)
    row = cursor.fetchone()
    if row:
        result["table_macro_exists"] = True
        try:
             cursor.execute("SELECT sql_macro FROM user_procedures WHERE object_name = 'GET_HIGH_IMPACT_SALES'")
             macro_type = cursor.fetchone()
             if macro_type and macro_type[0] == 'TABLE':
                 result["table_macro_is_macro"] = True
        except:
             pass

        # Test Logic: Count rows via Macro vs Ground Truth SQL
        # Region='EAST', Amount=500, Weekends only
        try:
            # Macro count
            cursor.execute("SELECT COUNT(*) FROM get_high_impact_sales('EAST', 500)")
            macro_count = cursor.fetchone()[0]
            
            # Ground truth count
            cursor.execute("""
                SELECT COUNT(*) FROM sales_ledger 
                WHERE region = 'EAST' 
                  AND amount >= 500
                  AND TO_CHAR(txn_date, 'DY', 'NLS_DATE_LANGUAGE=ENGLISH') IN ('SAT', 'SUN')
            """)
            gt_count = cursor.fetchone()[0]
            
            if macro_count == gt_count and gt_count > 0:
                result["table_macro_logic_score"] = 1.0
            else:
                print(f"Table macro logic mismatch: Macro={macro_count}, GT={gt_count}")
        except Exception as e:
            print(f"Table macro logic test failed: {e}")

    # 3. Validate Report File
    report_path = "/home/ga/Desktop/fiscal_impact_report.csv"
    if os.path.exists(report_path):
        result["report_exists"] = True
        
        # Calculate Ground Truth Report Data
        # Query: Sum Amount, Count Txn by Fiscal Year for EAST, >500, Weekend
        # Note: We need to implement the fiscal logic in python or SQL to verify
        gt_data = {}
        cursor.execute("""
            SELECT 
                CASE 
                    WHEN EXTRACT(MONTH FROM txn_date) >= 10 THEN EXTRACT(YEAR FROM txn_date) + 1
                    ELSE EXTRACT(YEAR FROM txn_date) 
                END as fy,
                SUM(amount),
                COUNT(*)
            FROM sales_ledger
            WHERE region = 'EAST' 
              AND amount >= 500
              AND TO_CHAR(txn_date, 'DY', 'NLS_DATE_LANGUAGE=ENGLISH') IN ('SAT', 'SUN')
            GROUP BY 
                CASE 
                    WHEN EXTRACT(MONTH FROM txn_date) >= 10 THEN EXTRACT(YEAR FROM txn_date) + 1
                    ELSE EXTRACT(YEAR FROM txn_date) 
                END
            ORDER BY fy ASC
        """)
        for row in cursor.fetchall():
            # key: fy, value: (sum, count)
            gt_data[str(row[0])] = (float(row[1]), int(row[2]))
            
        # Parse User CSV
        try:
            with open(report_path, 'r') as f:
                reader = csv.DictReader(f)
                # Normalize headers: remove spaces, uppercase
                headers = [h.strip().upper() for h in reader.fieldnames]
                if 'FISCAL_YEAR' in headers and 'TOTAL_AMOUNT' in headers and 'TXN_COUNT' in headers:
                    result["report_valid_format"] = True
                    
                    matches = 0
                    rows_checked = 0
                    
                    # Re-read to iterate
                    f.seek(0)
                    next(f) # skip header
                    # Handle raw reading to be robust against header naming variations if DictReader fails on strictness
                    csv_reader = csv.reader(f)
                    
                    for row in csv_reader:
                        if not row or len(row) < 3: continue
                        rows_checked += 1
                        u_fy = str(row[0]).strip()
                        u_amt = float(row[1])
                        u_cnt = int(row[2])
                        
                        if u_fy in gt_data:
                            gt_amt, gt_cnt = gt_data[u_fy]
                            # Allow small float tolerance
                            if abs(u_amt - gt_amt) < 1.0 and u_cnt == gt_cnt:
                                matches += 1
                    
                    if len(gt_data) > 0:
                        result["report_data_accuracy"] = matches / len(gt_data)
        except Exception as e:
            print(f"Report parsing failed: {e}")

    conn.close()

except Exception as e:
    result["db_error"] = str(e)
    print(f"DB Error: {e}")

# Save results
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)

PYEOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="