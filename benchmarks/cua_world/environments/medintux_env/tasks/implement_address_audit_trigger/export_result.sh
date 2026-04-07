#!/bin/bash
echo "=== Exporting implement_address_audit_trigger results ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot (evidence of agent's terminal or editor)
take_screenshot /tmp/task_final.png

# Path to the SQL file agent was supposed to create
SQL_FILE="/home/ga/audit_implementation.sql"
SQL_FILE_EXISTS="false"
if [ -f "$SQL_FILE" ]; then
    SQL_FILE_EXISTS="true"
fi

# ==============================================================================
# RUN VERIFICATION TESTS INSIDE THE CONTAINER
# ==============================================================================
# We use a python script to connect to DB, check schema, run a test update, 
# and verify the log was created. We output a JSON for the host verifier.

cat > /tmp/internal_verify.py << 'PYEOF'
import pymysql
import json
import time
import sys
import uuid

result = {
    "table_exists": False,
    "columns_correct": False,
    "trigger_exists": False,
    "functional_test_passed": False,
    "data_integrity_passed": False,
    "error": None
}

try:
    conn = pymysql.connect(host='localhost', user='root', password='', database='DrTuxTest', autocommit=True)
    cursor = conn.cursor()

    # 1. Check if table exists
    cursor.execute("SHOW TABLES LIKE 'address_audit_log'")
    if cursor.fetchone():
        result["table_exists"] = True
        
        # 2. Check columns
        cursor.execute("DESCRIBE address_audit_log")
        cols = {row[0].lower() for row in cursor.fetchall()}
        required_cols = {'patient_guid', 'old_address', 'new_address'}
        if required_cols.issubset(cols):
            result["columns_correct"] = True

    # 3. Check if trigger exists
    cursor.execute("SHOW TRIGGERS WHERE `Trigger` = 'trg_audit_address_update'")
    if cursor.fetchone():
        result["trigger_exists"] = True

    # 4. Functional Test
    if result["trigger_exists"] and result["table_exists"]:
        # Create a test patient
        test_guid = str(uuid.uuid4())[:30] # Limit length just in case
        old_addr = "123 Test Lane"
        new_addr = "456 Verified Blvd"
        
        # Insert raw patient (bypass MedinTux logic, just DB)
        # We need a dummy record in fchpat
        # Note: In real MedinTux schema, we often need IndexNomPrenom too, but trigger is on fchpat
        cursor.execute("""
            INSERT INTO fchpat (FchPat_GUID_Doss, FchPat_NomFille, FchPat_Adresse) 
            VALUES (%s, 'TEST_PATIENT', %s)
        """, (test_guid, old_addr))
        
        # Update the address
        cursor.execute("""
            UPDATE fchpat SET FchPat_Adresse = %s WHERE FchPat_GUID_Doss = %s
        """, (new_addr, test_guid))
        
        # Check the log
        cursor.execute("""
            SELECT old_address, new_address, change_date 
            FROM address_audit_log 
            WHERE patient_guid = %s 
            ORDER BY log_id DESC LIMIT 1
        """, (test_guid,))
        
        row = cursor.fetchone()
        if row:
            result["functional_test_passed"] = True
            log_old, log_new, log_date = row
            
            # Verify data integrity
            # Handle potential None/empty string mismatches depending on implementation
            if str(log_old).strip() == old_addr and str(log_new).strip() == new_addr:
                result["data_integrity_passed"] = True
            
        # Clean up test data
        cursor.execute("DELETE FROM fchpat WHERE FchPat_GUID_Doss = %s", (test_guid,))
        cursor.execute("DELETE FROM address_audit_log WHERE patient_guid = %s", (test_guid,))

except Exception as e:
    result["error"] = str(e)
finally:
    if 'conn' in locals() and conn:
        conn.close()

print(json.dumps(result))
PYEOF

# Run the verification script
VERIFY_OUTPUT=$(python3 /tmp/internal_verify.py 2>/dev/null || echo '{"error": "Script failed"}')

# Create the final result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "sql_file_exists": $SQL_FILE_EXISTS,
    "db_verification": $VERIFY_OUTPUT
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Verification results:"
cat /tmp/task_result.json
echo "=== Export complete ==="