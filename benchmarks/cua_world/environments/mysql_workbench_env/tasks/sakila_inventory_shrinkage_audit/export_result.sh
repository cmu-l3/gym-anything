#!/bin/bash
# Export script for sakila_inventory_shrinkage_audit task

echo "=== Exporting Shrinkage Audit Result ==="

source /workspace/scripts/task_utils.sh
take_screenshot /tmp/task_end_screenshot.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 1. Check Staging Table
TABLE_EXISTS=$(mysql -u root -p'GymAnything#2024' sakila -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='sakila' AND table_name='inventory_audit'" 2>/dev/null)
TABLE_ROWS=0
if [ "$TABLE_EXISTS" -eq 1 ]; then
    TABLE_ROWS=$(mysql -u root -p'GymAnything#2024' sakila -N -e "SELECT COUNT(*) FROM inventory_audit" 2>/dev/null)
fi

# 2. Check Function
FUNCTION_EXISTS=$(mysql -u root -p'GymAnything#2024' sakila -N -e "SELECT COUNT(*) FROM information_schema.routines WHERE routine_schema='sakila' AND routine_name='fn_get_shrinkage_status'" 2>/dev/null)

# Verify Function Logic (if exists)
FUNCTION_LOGIC_TEST="fail"
if [ "$FUNCTION_EXISTS" -eq 1 ]; then
    # Test MISSING case (System 5, Actual 3)
    TEST_RES=$(mysql -u root -p'GymAnything#2024' sakila -N -e "SELECT fn_get_shrinkage_status(5, 3)" 2>/dev/null)
    if [ "$TEST_RES" == "MISSING" ]; then
        FUNCTION_LOGIC_TEST="pass"
    fi
fi

# 3. Check View
VIEW_EXISTS=$(mysql -u root -p'GymAnything#2024' sakila -N -e "SELECT COUNT(*) FROM information_schema.views WHERE table_schema='sakila' AND table_name='v_store1_shrinkage_report'" 2>/dev/null)

# 4. Check View Content (Does it catch the discrepancies?)
# We specifically check for Film ID 1 (Injected MISSING) and Film ID 2 (Injected EXTRA)
VIEW_CHECK_JSON="{}"
if [ "$VIEW_EXISTS" -eq 1 ]; then
    VIEW_CHECK_JSON=$(python3 -c "
import pymysql
import json
try:
    conn = pymysql.connect(host='localhost', user='root', password='GymAnything#2024', database='sakila')
    cursor = conn.cursor(pymysql.cursors.DictCursor)
    
    # Query the student's view for our known discrepancies
    cursor.execute(\"SELECT * FROM v_store1_shrinkage_report WHERE film_id IN (1, 2, 10)\")
    rows = cursor.fetchall()
    
    results = {}
    for r in rows:
        results[r['film_id']] = {
            'variance': r.get('variance'),
            'status': r.get('status')
        }
    print(json.dumps(results))
except Exception as e:
    print(json.dumps({'error': str(e)}))
")
fi

# 5. Check Export File
EXPORT_FILE="/home/ga/Documents/exports/shrinkage_report.csv"
FILE_EXISTS="false"
FILE_ROWS=0
FILE_CREATED_DURING_TASK="false"

if [ -f "$EXPORT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c%Y "$EXPORT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    FILE_ROWS=$(wc -l < "$EXPORT_FILE" 2>/dev/null)
fi

# Construct Result JSON
cat > /tmp/task_result.json << EOF
{
    "table_exists": $TABLE_EXISTS,
    "table_rows": ${TABLE_ROWS:-0},
    "function_exists": $FUNCTION_EXISTS,
    "function_logic_pass": "$FUNCTION_LOGIC_TEST",
    "view_exists": $VIEW_EXISTS,
    "view_content_check": $VIEW_CHECK_JSON,
    "file_exists": $FILE_EXISTS,
    "file_rows": ${FILE_ROWS:-0},
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "task_start_time": $TASK_START
}
EOF

cat /tmp/task_result.json
echo "=== Export Complete ==="