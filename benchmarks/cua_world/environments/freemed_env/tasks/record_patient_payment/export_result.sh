#!/bin/bash
# Export task: record_patient_payment

echo "=== Exporting record_patient_payment result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_payment_end.png

# Query the database to see if financial tables have new rows
PAYREC_NOW=$(freemed_query "SELECT COUNT(*) FROM payrec" 2>/dev/null || echo "0")
PAYMENT_NOW=$(freemed_query "SELECT COUNT(*) FROM payment" 2>/dev/null || echo "0")
BILLING_NOW=$(freemed_query "SELECT COUNT(*) FROM patient_billing" 2>/dev/null || echo "0")

PAYREC_START=$(cat /tmp/initial_payrec_count 2>/dev/null || echo "0")
PAYMENT_START=$(cat /tmp/initial_payment_count 2>/dev/null || echo "0")
BILLING_START=$(cat /tmp/initial_billing_count 2>/dev/null || echo "0")

# Check if any financial records were added (Anti-gaming check)
DB_RECORD_ADDED="false"
if [ "$PAYREC_NOW" -gt "$PAYREC_START" ] || [ "$PAYMENT_NOW" -gt "$PAYMENT_START" ] || [ "$BILLING_NOW" -gt "$BILLING_START" ]; then
    DB_RECORD_ADDED="true"
fi

# Try to find exactly matching payment value to reward accuracy at DB level if schema allows it
# We check if 35.00 appears in recent rows. Due to varying schemas, we use an approximation:
EXACT_AMOUNT_FOUND="false"
if [ "$DB_RECORD_ADDED" = "true" ]; then
    # Look for '35' in recent rows across these tables
    PAYREC_VALS=$(freemed_query "SELECT * FROM payrec WHERE id > (SELECT MAX(id)-10 FROM payrec)" 2>/dev/null || echo "")
    if echo "$PAYREC_VALS" | grep -q "35"; then
        EXACT_AMOUNT_FOUND="true"
    fi
fi

# Create export JSON file
TEMP_JSON=$(mktemp /tmp/payment_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_counts": {
        "payrec": $PAYREC_START,
        "payment": $PAYMENT_START,
        "billing": $BILLING_START
    },
    "current_counts": {
        "payrec": $PAYREC_NOW,
        "payment": $PAYMENT_NOW,
        "billing": $BILLING_NOW
    },
    "db_record_added": $DB_RECORD_ADDED,
    "exact_amount_found": $EXACT_AMOUNT_FOUND,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final destination safely
rm -f /tmp/payment_result.json 2>/dev/null || sudo rm -f /tmp/payment_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/payment_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/payment_result.json
chmod 666 /tmp/payment_result.json 2>/dev/null || sudo chmod 666 /tmp/payment_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Database changes detected: $DB_RECORD_ADDED"
echo "=== Export complete ==="