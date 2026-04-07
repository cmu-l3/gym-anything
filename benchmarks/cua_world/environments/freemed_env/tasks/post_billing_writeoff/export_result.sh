#!/bin/bash
echo "=== Exporting post_billing_writeoff Result ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

take_screenshot /tmp/task_final_state.png

PATIENT_ID=$(cat /tmp/target_patient_id 2>/dev/null || echo "0")
MAX_PAYMENT_ID=$(cat /tmp/max_payment_id 2>/dev/null || echo "0")
MAX_BILLING_ID=$(cat /tmp/max_billing_id 2>/dev/null || echo "0")
MAX_PROCREC_ID=$(cat /tmp/max_procrec_id 2>/dev/null || echo "0")

# Extract new payments
NEW_PAYMENTS=$(freemed_query "SELECT id, amount, paymethod FROM payment WHERE id > $MAX_PAYMENT_ID AND patient=$PATIENT_ID" 2>/dev/null)
# Extract new billing
NEW_BILLING=$(freemed_query "SELECT id, amount, billing_type FROM billing WHERE id > $MAX_BILLING_ID AND patient=$PATIENT_ID" 2>/dev/null)
# Extract new procrec (some systems use negative charge for adjustment)
NEW_PROCREC=$(freemed_query "SELECT id, proccharge, 'Charge' FROM procrec WHERE id > $MAX_PROCREC_ID AND ppatient=$PATIENT_ID" 2>/dev/null)

# Generate JSON directly using Python for safe formatting
python3 -c "
import json

def parse_tsv(data, cols):
    if not data or not data.strip(): return []
    res = []
    for line in data.strip().split('\n'):
        parts = line.split('\t')
        record = {}
        for i, col in enumerate(cols):
            if i < len(parts): record[col] = parts[i]
        res.append(record)
    return res

payments = parse_tsv('''$NEW_PAYMENTS''', ['id', 'amount', 'type'])
billing = parse_tsv('''$NEW_BILLING''', ['id', 'amount', 'type'])
procrec = parse_tsv('''$NEW_PROCREC''', ['id', 'amount', 'type'])

result = {
    'task_start': int('$TASK_START'),
    'task_end': int('$TASK_END'),
    'patient_id': '$PATIENT_ID',
    'new_payments': payments,
    'new_billing': billing,
    'new_procrec': procrec,
    'screenshot_path': '/tmp/task_final_state.png'
}

with open('/tmp/post_billing_writeoff_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

chmod 666 /tmp/post_billing_writeoff_result.json 2>/dev/null || true

echo "Result saved to /tmp/post_billing_writeoff_result.json"
cat /tmp/post_billing_writeoff_result.json
echo "=== Export Complete ==="