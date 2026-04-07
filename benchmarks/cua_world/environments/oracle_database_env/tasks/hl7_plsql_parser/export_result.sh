#!/bin/bash
# Export script for HL7 Parser task
# Validates the PATIENT_ADMISSIONS table structure and content

set -e

echo "=== Exporting HL7 Parser Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Prepare Python script to extract results robustly using oracledb
# We use Python because parsing DB outputs in bash is fragile, especially with dates/nulls
cat > /tmp/check_hl7_results.py << 'EOF'
import oracledb
import json
import datetime
import sys

# Custom JSON encoder for dates
class DateTimeEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, (datetime.date, datetime.datetime)):
            return obj.isoformat()
        return super(DateTimeEncoder, self).default(obj)

result = {
    "table_exists": False,
    "columns_correct": False,
    "row_count": 0,
    "sentinel_found": False,
    "sentinel_data": {},
    "procedure_exists": False,
    "procedure_status": "UNKNOWN",
    "errors": []
}

try:
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # 1. Check Table Existence
    cursor.execute("SELECT count(*) FROM user_tables WHERE table_name = 'PATIENT_ADMISSIONS'")
    if cursor.fetchone()[0] > 0:
        result["table_exists"] = True
        
        # 2. Check Columns
        required_cols = {'MRN', 'PATIENT_NAME', 'ADMISSION_DATE', 'MESSAGE_EVENT', 'DIAGNOSIS_CODE'}
        cursor.execute("SELECT column_name FROM user_tab_columns WHERE table_name = 'PATIENT_ADMISSIONS'")
        found_cols = {row[0] for row in cursor.fetchall()}
        missing = required_cols - found_cols
        if not missing:
            result["columns_correct"] = True
        else:
            result["errors"].append(f"Missing columns: {list(missing)}")

        # 3. Check Row Count
        cursor.execute("SELECT count(*) FROM PATIENT_ADMISSIONS")
        result["row_count"] = cursor.fetchone()[0]

        # 4. Check Sentinel Record (MRN = TEST999)
        # We handle case sensitivity by checking exact match first
        cursor.execute("""
            SELECT mrn, patient_name, admission_date, message_event, diagnosis_code 
            FROM PATIENT_ADMISSIONS 
            WHERE mrn = 'TEST999'
        """)
        row = cursor.fetchone()
        if row:
            result["sentinel_found"] = True
            result["sentinel_data"] = {
                "mrn": row[0],
                "patient_name": row[1],
                "admission_date": row[2], # Will be serialized by encoder
                "message_event": row[3],
                "diagnosis_code": row[4]
            }
        else:
            result["errors"].append("Sentinel record TEST999 not found")

    else:
        result["errors"].append("Table PATIENT_ADMISSIONS not found")

    # 5. Check Procedure Existence
    cursor.execute("SELECT status FROM user_objects WHERE object_name = 'PARSE_HL7_BATCH' AND object_type = 'PROCEDURE'")
    row = cursor.fetchone()
    if row:
        result["procedure_exists"] = True
        result["procedure_status"] = row[0]

except Exception as e:
    result["errors"].append(str(e))
finally:
    try:
        if 'conn' in locals(): conn.close()
    except:
        pass

# Write result
with open('/tmp/hl7_result.json', 'w') as f:
    json.dump(result, f, cls=DateTimeEncoder, indent=2)

EOF

# Execute the python script inside the container? 
# NO, we can execute it on the host if we have python + oracledb installed.
# The env has `python3-pip` and `oracledb` installed in `install_oracle.sh`.
# So we run this inside the container to be safe about connection strings/network.
# Wait, the prompt says "verifier.py - Verification logic (runs on host machine)".
# But export_result.sh runs in the container (via hooks).
# We can run python in the container.

# Ensure python script permissions
chmod 644 /tmp/check_hl7_results.py

# Run verification script inside container (as user ga or root, ensuring access to oracledb)
# Note: install_oracle.sh installed pip packages globally or for root. 
# We'll use sudo to ensure we can load the libraries.
sudo python3 /tmp/check_hl7_results.py

# Move result to safe location for extraction
cp /tmp/hl7_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export completed. Result:"
cat /tmp/task_result.json