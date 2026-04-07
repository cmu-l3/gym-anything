#!/bin/bash
set -e
echo "=== Exporting post_insurance_eob results ==="

# 1. Capture timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
PID=$(cat /tmp/patient_pid.txt 2>/dev/null || echo "0")

# 2. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 3. Query Database for Results
# We dump relevant tables for the patient to JSON for the verifier to parse
# We look for billing_core records created/modified recently
# Note: NOSH often stores payments in 'billing_core' with specific flags or 'accounts_receivable'
# We will dump billing_core for the patient
echo "Querying database for PID $PID..."

# Helper for JSON export
export_query_to_json() {
    QUERY="$1"
    docker exec nosh-db mysql -uroot -prootpassword nosh -e "$QUERY" --xml | \
    python3 -c '
import sys
import xml.etree.ElementTree as ET
import json

try:
    tree = ET.parse(sys.stdin)
    root = tree.getroot()
    rows = []
    for row in root.findall("row"):
        d = {}
        for field in row.findall("field"):
            d[field.get("name")] = field.text
        rows.append(d)
    print(json.dumps(rows))
except Exception as e:
    print("[]")
'
}

# Dump all billing items for this patient
BILLING_RECORDS=$(export_query_to_json "SELECT * FROM billing_core WHERE pid=$PID ORDER BY billing_core_id DESC")

# Also check for a dedicated payments table if it exists (e.g. billing_payments, ar_session)
# NOSH schema varies, so we check billing_core primarily, but let's check for "payments" keyword in tables
PAYMENT_RECORDS="[]"
if docker exec nosh-db mysql -uroot -prootpassword nosh -e "SHOW TABLES LIKE 'payments'" | grep -q payments; then
    PAYMENT_RECORDS=$(export_query_to_json "SELECT * FROM payments WHERE pid=$PID")
fi

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "patient_pid": "$PID",
    "billing_records": $BILLING_RECORDS,
    "payment_records": $PAYMENT_RECORDS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 5. Save to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"