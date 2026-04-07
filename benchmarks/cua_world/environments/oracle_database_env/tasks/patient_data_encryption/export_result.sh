#!/bin/bash
# Export script for Patient Data Encryption task
# Verifies the database schema and data state

set -e

echo "=== Exporting Patient Data Encryption Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Use Python to inspect the database state robustly
python3 << 'PYEOF'
import oracledb
import json
import os
import re

result = {
    "keystore_exists": False,
    "key_valid": False,
    "encrypt_func_valid": False,
    "decrypt_func_valid": False,
    "ssn_encrypted_col_exists": False,
    "diag_encrypted_col_exists": False,
    "ssn_encrypted_type": "",
    "ssn_plaintext_dropped": True,
    "diag_plaintext_dropped": True,
    "encrypted_data_count": 0,
    "decryption_test_passed": False,
    "view_exists": False,
    "view_count": 0,
    "view_columns": [],
    "report_exists": False,
    "report_size": 0
}

try:
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # 1. Check Key Store
    try:
        cursor.execute("SELECT key_value FROM encryption_key_store WHERE key_id = 1")
        row = cursor.fetchone()
        if row:
            result["keystore_exists"] = True
            # Check key length (should be 32 bytes for AES-256)
            key_len = len(row[0].read()) if hasattr(row[0], 'read') else len(row[0])
            if key_len >= 32:
                result["key_valid"] = True
    except Exception:
        pass

    # 2. Check Functions
    cursor.execute("SELECT object_name, status FROM user_objects WHERE object_type = 'FUNCTION' AND object_name IN ('ENCRYPT_VALUE', 'DECRYPT_VALUE')")
    for name, status in cursor.fetchall():
        if name == 'ENCRYPT_VALUE' and status == 'VALID':
            result["encrypt_func_valid"] = True
        if name == 'DECRYPT_VALUE' and status == 'VALID':
            result["decrypt_func_valid"] = True

    # 3. Check Table Columns
    cursor.execute("SELECT column_name, data_type FROM user_tab_columns WHERE table_name = 'PATIENT_RECORDS'")
    cols = {row[0]: row[1] for row in cursor.fetchall()}
    
    if 'SSN_ENCRYPTED' in cols:
        result["ssn_encrypted_col_exists"] = True
        result["ssn_encrypted_type"] = cols['SSN_ENCRYPTED']
    
    if 'DIAGNOSIS_ENCRYPTED' in cols:
        result["diag_encrypted_col_exists"] = True
    
    if 'SSN' in cols:
        result["ssn_plaintext_dropped"] = False
    
    if 'DIAGNOSIS_CODE' in cols:
        result["diag_plaintext_dropped"] = False

    # 4. Check Data Content
    if result["ssn_encrypted_col_exists"]:
        cursor.execute("SELECT COUNT(*) FROM patient_records WHERE ssn_encrypted IS NOT NULL")
        result["encrypted_data_count"] = cursor.fetchone()[0]

    # 5. Test Decryption (Verification of Logic)
    if result["decrypt_func_valid"] and result["ssn_encrypted_col_exists"] and result["encrypted_data_count"] > 0:
        try:
            # Pick a sample encrypted value and try to decrypt it via the user's function
            cursor.execute("SELECT decrypt_value(ssn_encrypted) FROM patient_records FETCH FIRST 1 ROWS ONLY")
            decrypted_ssn = cursor.fetchone()[0]
            # Simple regex check for SSN format XXX-XX-XXXX
            if re.match(r'^\d{3}-\d{2}-\d{4}$', decrypted_ssn):
                result["decryption_test_passed"] = True
        except Exception as e:
            result["decryption_error"] = str(e)

    # 6. Check View
    try:
        cursor.execute("SELECT COUNT(*) FROM patient_records_vw")
        result["view_count"] = cursor.fetchone()[0]
        result["view_exists"] = True
        
        cursor.execute("SELECT column_name FROM user_tab_columns WHERE table_name = 'PATIENT_RECORDS_VW'")
        result["view_columns"] = [row[0] for row in cursor.fetchall()]
    except Exception:
        pass

    cursor.close()
    conn.close()

except Exception as e:
    result["error"] = str(e)

# 7. Check Report File
report_path = "/home/ga/Desktop/encryption_report.txt"
if os.path.exists(report_path):
    result["report_exists"] = True
    result["report_size"] = os.path.getsize(report_path)

# Save Result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Export complete. Result saved to /tmp/task_result.json"