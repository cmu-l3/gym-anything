#!/bin/bash
echo "=== Exporting Audit Trail Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DB="DrTuxTest"
VERIFY_GUID="AUDIT-VERIFY-001"

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check Report File
REPORT_PATH="/home/ga/audit_trail_report.txt"
REPORT_EXISTS="false"
REPORT_SIZE="0"
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH")
fi

# 2. Database Inspection (Export data for verifier)
echo "Inspecting database..."

# Check Table Existence and Schema
TABLE_CHECK=$(mysql -u root $DB -e "DESCRIBE patient_audit_log" 2>/dev/null || echo "MISSING")

# Get Trigger List
TRIGGERS=$(mysql -u root $DB -N -e "SHOW TRIGGERS" 2>/dev/null | cut -f1)

# Get Audit Log Content (limit to recent entries to keep JSON small)
# dump as JSON-like list of dicts using python helper if needed, or just raw lines
# We'll stick to a simple query dump we can parse in python
LOG_CONTENT=$(mysql -u root $DB -e "SELECT operation_type, table_name, record_id, changed_at FROM patient_audit_log ORDER BY audit_id DESC LIMIT 20" 2>/dev/null)

# 3. FUNCTIONAL VERIFICATION (Run inside container)
# We perform an INSERT and DELETE on a verify record and check if the audit log catches it.
# This proves the triggers are actually ACTIVE and working.
echo "Running functional verification..."

FUNCTIONAL_TEST_PASSED="false"
VERIFY_LOG_FOUND="false"

# Perform Verify Action
mysql -u root $DB -e "INSERT IGNORE INTO IndexNomPrenom (FchGnrl_IDDos, FchGnrl_NomDos, FchGnrl_Prenom, FchGnrl_Type) VALUES ('$VERIFY_GUID', 'AUDITVERIFY', 'Robot', 'Dossier')" 2>/dev/null
sleep 1
mysql -u root $DB -e "DELETE FROM IndexNomPrenom WHERE FchGnrl_IDDos='$VERIFY_GUID'" 2>/dev/null

# Check if these actions appeared in the log
VERIFY_CHECK=$(mysql -u root $DB -N -e "SELECT COUNT(*) FROM patient_audit_log WHERE record_id='$VERIFY_GUID'" 2>/dev/null || echo "0")

if [ "$VERIFY_CHECK" -ge 2 ]; then
    FUNCTIONAL_TEST_PASSED="true"
    echo "Functional test passed: found $VERIFY_CHECK audit entries for verify GUID."
else
    echo "Functional test failed: found $VERIFY_CHECK audit entries."
fi

# Clean up verification data (optional, but polite)
mysql -u root $DB -e "DELETE FROM IndexNomPrenom WHERE FchGnrl_IDDos='$VERIFY_GUID'" 2>/dev/null || true

# 4. Construct JSON Result
TEMP_JSON=$(mktemp /tmp/audit_result.XXXXXX.json)

# Python script to JSON-ify the bash variables safely
python3 -c "
import json
import os
import sys

result = {
    'task_start': $TASK_START,
    'report_exists': $REPORT_EXISTS,
    'report_size': $REPORT_SIZE,
    'table_schema_output': '''$TABLE_CHECK''',
    'triggers_found': '''$TRIGGERS'''.split(),
    'log_content_sample': '''$LOG_CONTENT''',
    'functional_test_passed': $FUNCTIONAL_TEST_PASSED,
    'verify_guid': '$VERIFY_GUID'
}
print(json.dumps(result, indent=2))
" > "$TEMP_JSON"

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="