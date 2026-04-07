#!/bin/bash
# Export script for bulk_migration_save_exceptions task

set -e
echo "=== Exporting Bulk Migration Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Use Python for reliable data extraction (querying DB and parsing source code)
python3 << 'PYEOF'
import oracledb
import json
import re

result = {
    "ground_truth_total": 0,
    "ground_truth_bad": 0,
    "target_count": 0,
    "error_log_count": 0,
    "error_samples": [],
    "procedure_exists": False,
    "procedure_status": "INVALID",
    "source_code": "",
    "keywords_found": {
        "bulk_collect": False,
        "forall": False,
        "save_exceptions": False,
        "bulk_exceptions": False,
        "limit": False
    },
    "db_error": None
}

try:
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # 1. Get Ground Truth from hidden table
    try:
        cursor.execute("SELECT value_num FROM task_metadata_hidden WHERE key_name = 'TOTAL_ROWS'")
        row = cursor.fetchone()
        if row: result["ground_truth_total"] = row[0]
        
        cursor.execute("SELECT value_num FROM task_metadata_hidden WHERE key_name = 'BAD_ROWS'")
        row = cursor.fetchone()
        if row: result["ground_truth_bad"] = row[0]
    except Exception:
        pass # Table might not exist if setup failed

    # 2. Get Actual Counts
    cursor.execute("SELECT COUNT(*) FROM fact_sales_prod")
    result["target_count"] = cursor.fetchone()[0]

    cursor.execute("SELECT COUNT(*) FROM migration_errors")
    result["error_log_count"] = cursor.fetchone()[0]

    # 3. Sample Errors
    cursor.execute("SELECT error_message FROM migration_errors FETCH FIRST 5 ROWS ONLY")
    result["error_samples"] = [row[0] for row in cursor.fetchall()]

    # 4. Check Procedure Source Code
    cursor.execute("""
        SELECT status 
        FROM user_objects 
        WHERE object_name = 'MIGRATE_SALES_BULK' AND object_type = 'PROCEDURE'
    """)
    row = cursor.fetchone()
    if row:
        result["procedure_exists"] = True
        result["procedure_status"] = row[0]
        
        # Get Source
        cursor.execute("""
            SELECT text 
            FROM user_source 
            WHERE name = 'MIGRATE_SALES_BULK' AND type = 'PROCEDURE'
            ORDER BY line
        """)
        source_lines = [row[0] for row in cursor.fetchall()]
        full_source = "".join(source_lines).upper()
        result["source_code"] = full_source # storing strictly for debugging if needed, usually too large
        
        # Check Keywords (Case insensitive via upper)
        # We look for variations to be robust
        result["keywords_found"]["bulk_collect"] = "BULK COLLECT" in full_source
        result["keywords_found"]["forall"] = "FORALL" in full_source
        result["keywords_found"]["save_exceptions"] = "SAVE EXCEPTIONS" in full_source
        result["keywords_found"]["limit"] = "LIMIT" in full_source
        
        # %BULK_EXCEPTIONS check
        result["keywords_found"]["bulk_exceptions"] = "%BULK_EXCEPTIONS" in full_source

    cursor.close()
    conn.close()

except Exception as e:
    result["db_error"] = str(e)

# Save Result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="
cat /tmp/task_result.json