#!/bin/bash
# Export script for sakila_inventory_lifecycle_management task

echo "=== Exporting Sakila Lifecycle Result ==="

source /workspace/scripts/task_utils.sh
take_screenshot /tmp/task_end_screenshot.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/Documents/exports/unavailable_inventory.csv"

# We use a Python script to perform robust verification of the database logic
# This checks schema, data, and - critically - tries to trigger the business rules
# to see if they actually enforce the constraints (which static analysis might miss).

cat > /tmp/verify_db_logic.py << 'PYEOF'
import pymysql
import json
import os
import sys

def verify():
    results = {
        "schema_status_col_exists": False,
        "schema_status_type_correct": False,
        "proc_exists": False,
        "trigger_exists": False,
        "proc_logic_enforced": False,
        "trigger_logic_enforced": False,
        "data_item_10_status": None,
        "data_item_11_status": None
    }

    try:
        conn = pymysql.connect(
            host='localhost',
            user='ga',
            password='password123',
            database='sakila',
            cursorclass=pymysql.cursors.DictCursor
        )
        
        with conn.cursor() as cursor:
            # 1. Check Schema
            cursor.execute("SHOW COLUMNS FROM inventory LIKE 'status'")
            col = cursor.fetchone()
            if col:
                results["schema_status_col_exists"] = True
                # Check ENUM definition roughly
                if "enum" in col['Type'].lower() and "active" in col['Type'].lower() and "damaged" in col['Type'].lower():
                    results["schema_status_type_correct"] = True

            # 2. Check Objects Existence
            cursor.execute("SELECT COUNT(*) as cnt FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA='sakila' AND ROUTINE_NAME='sp_set_inventory_status'")
            if cursor.fetchone()['cnt'] > 0:
                results["proc_exists"] = True

            cursor.execute("SELECT COUNT(*) as cnt FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA='sakila' AND TRIGGER_NAME='trg_prevent_renting_unavailable'")
            if cursor.fetchone()['cnt'] > 0:
                results["trigger_exists"] = True

            # 3. Check Data State
            if results["schema_status_col_exists"]:
                cursor.execute("SELECT inventory_id, status FROM inventory WHERE inventory_id IN (10, 11)")
                rows = cursor.fetchall()
                for row in rows:
                    if row['inventory_id'] == 10:
                        results["data_item_10_status"] = row['status']
                    elif row['inventory_id'] == 11:
                        results["data_item_11_status"] = row['status']

            # 4. TEST PROCEDURE LOGIC: Try to change status of RENTED item (ID 1)
            # Item 1 was set to rented in setup_task.sh
            if results["proc_exists"]:
                try:
                    cursor.execute("CALL sp_set_inventory_status(1, 'Damaged')")
                    # If we get here, it succeeded, which is WRONG
                    results["proc_logic_enforced"] = False
                except pymysql.err.MySQLError as e:
                    # We expect an error (Signal 45000)
                    if e.args[0] == 45000 or "rented" in str(e).lower():
                        results["proc_logic_enforced"] = True

            # 5. TEST TRIGGER LOGIC: Try to rent a DAMAGED item (ID 10)
            # We assume Item 10 is 'Damaged' (checked in step 3). If not, we temporarily force it for test?
            # Better: If step 3 says it's Damaged, we test. 
            if results["data_item_10_status"] == 'Damaged' and results["trigger_exists"]:
                try:
                    # Try to insert a new rental for item 10
                    # Using dummy customer 1, staff 1
                    cursor.execute("""
                        INSERT INTO rental (rental_date, inventory_id, customer_id, return_date, staff_id) 
                        VALUES (NOW(), 10, 1, NULL, 1)
                    """)
                    # If success, trigger failed
                    results["trigger_logic_enforced"] = False
                    # Cleanup
                    conn.rollback()
                except pymysql.err.MySQLError as e:
                    # We expect an error
                    if e.args[0] == 45000 or "available" in str(e).lower():
                        results["trigger_logic_enforced"] = True
            
    except Exception as e:
        results["error"] = str(e)
    finally:
        if 'conn' in locals() and conn.open:
            conn.close()

    print(json.dumps(results))

if __name__ == "__main__":
    verify()
PYEOF

# Run the python verification
DB_RESULTS=$(python3 /tmp/verify_db_logic.py)

# Check CSV export
CSV_EXISTS="false"
CSV_ROWS=0
CSV_MTIME=0
if [ -f "$OUTPUT_FILE" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c%Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    # subtract header
    TOTAL=$(wc -l < "$OUTPUT_FILE" 2>/dev/null || echo "0")
    CSV_ROWS=$((TOTAL - 1))
fi

# Combine results
cat > /tmp/task_result.json << EOF
{
    "db_verification": $DB_RESULTS,
    "csv_exists": $CSV_EXISTS,
    "csv_rows": $CSV_ROWS,
    "csv_mtime": $CSV_MTIME,
    "task_start": $TASK_START,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Verification Results:"
cat /tmp/task_result.json
echo "=== Export Complete ==="