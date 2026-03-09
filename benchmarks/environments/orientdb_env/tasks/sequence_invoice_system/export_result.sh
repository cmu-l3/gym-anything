#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting sequence_invoice_system result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# --- DATA GATHERING ---

# 1. Check invoiceIdSeq
SEQ1_JSON=$(orientdb_sql "demodb" "SELECT sequence('invoiceIdSeq').current() as val")
SEQ1_VAL=$(echo "$SEQ1_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('result', [{}])[0].get('val', 'NOTFOUND'))" 2>/dev/null || echo "NOTFOUND")

# 2. Check receiptSeq
# Try current() first; if it returns null (unused), try next() just to verify existence
SEQ2_JSON=$(orientdb_sql "demodb" "SELECT sequence('receiptSeq').current() as val")
SEQ2_VAL=$(echo "$SEQ2_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('result', [{}])[0].get('val', 'NOTFOUND'))" 2>/dev/null || echo "NOTFOUND")
if [ "$SEQ2_VAL" = "NOTFOUND" ] || [ -z "$SEQ2_VAL" ]; then
    SEQ2_JSON=$(orientdb_sql "demodb" "SELECT sequence('receiptSeq').next() as val")
    SEQ2_VAL=$(echo "$SEQ2_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('result', [{}])[0].get('val', 'NOTFOUND'))" 2>/dev/null || echo "NOTFOUND")
fi

# 3. Check Schema (Class & Index)
SCHEMA_JSON=$(curl -s -u "${ORIENTDB_AUTH}" "${ORIENTDB_URL}/database/demodb")

# 4. Check Records
RECORDS_JSON=$(orientdb_sql "demodb" "SELECT InvoiceId, CustomerEmail, Amount, Currency, IssuedDate, Description, Status FROM Invoices ORDER BY InvoiceId ASC")
RECORD_COUNT=$(echo "$RECORDS_JSON" | python3 -c "import sys, json; print(len(json.load(sys.stdin).get('result', [])))" 2>/dev/null || echo "0")

# 5. Check Initial Count
INITIAL_COUNT=$(cat /tmp/initial_invoice_count.txt 2>/dev/null || echo "0")

# 6. Check if Firefox is running
APP_RUNNING=$(pgrep -f firefox > /dev/null && echo "true" || echo "false")

# Assemble the JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# We use Python to robustly construct the final JSON to avoid shell escaping hell
python3 -c "
import json
import os

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'app_was_running': $APP_RUNNING,
    'initial_count': int('$INITIAL_COUNT'),
    'record_count': int('$RECORD_COUNT'),
    'seq1_val': '$SEQ1_VAL',
    'seq2_val': '$SEQ2_VAL',
    'schema': json.loads('''$SCHEMA_JSON'''),
    'records': json.loads('''$RECORDS_JSON''').get('result', [])
}

with open('$TEMP_JSON', 'w') as f:
    json.dump(result, f, indent=2)
"

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="