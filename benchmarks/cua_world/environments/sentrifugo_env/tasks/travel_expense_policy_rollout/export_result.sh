#!/bin/bash
echo "=== Exporting travel_expense_policy_rollout result ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Find all tables related to Expenses and Payments
# This approach is highly robust against schema changes while preventing the agent 
# from gaming the test by entering the text into random fields (like Announcements).
echo "Extracting relevant DB tables..."
TABLES=$(docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -e "SELECT table_name FROM information_schema.tables WHERE table_schema='sentrifugo' AND (table_name LIKE '%expense%' OR table_name LIKE '%payment%');" | tr '\n' ' ')

if [ -n "$TABLES" ]; then
    # Dump only the relevant tables, using skip-extended-insert to put one record per line for easy grepping
    docker exec sentrifugo-db mysqldump -u root -prootpass123 sentrifugo $TABLES --skip-extended-insert > /tmp/te_dump.sql
else
    touch /tmp/te_dump.sql
fi

# Initialize boolean flags
HAS_CAT_INTL="false"
HAS_CAT_LODGING="false"
HAS_CAT_CLIENT="false"
HAS_CAT_CONF="false"
HAS_PAY_AMEX="false"
HAS_PAY_PERSONAL="false"
HAS_REQ_TITLE="false"
HAS_REQ_AMOUNT="false"

# Check for existence of the expected strings in the relevant database dump
grep -qi "International Airfare" /tmp/te_dump.sql && HAS_CAT_INTL="true"
grep -qi "Domestic Lodging" /tmp/te_dump.sql && HAS_CAT_LODGING="true"
grep -qi "Client Entertainment" /tmp/te_dump.sql && HAS_CAT_CLIENT="true"
grep -qi "Conference Registration" /tmp/te_dump.sql && HAS_CAT_CONF="true"

grep -qi "Corporate AMEX" /tmp/te_dump.sql && HAS_PAY_AMEX="true"
grep -qi "Personal Credit Card" /tmp/te_dump.sql && HAS_PAY_PERSONAL="true"

grep -qi "Q3 Sales Conference Tokyo" /tmp/te_dump.sql && HAS_REQ_TITLE="true"
# Match the amount either as integer or decimal
grep -qE "1450(\.00)?" /tmp/te_dump.sql && HAS_REQ_AMOUNT="true"

# Construct JSON payload
TEMP_JSON=$(mktemp /tmp/te_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "categories": {
        "intl_airfare": $HAS_CAT_INTL,
        "domestic_lodging": $HAS_CAT_LODGING,
        "client_entertainment": $HAS_CAT_CLIENT,
        "conference_registration": $HAS_CAT_CONF
    },
    "payment_methods": {
        "corporate_amex": $HAS_PAY_AMEX,
        "personal_credit_card": $HAS_PAY_PERSONAL
    },
    "expense_request": {
        "title_found": $HAS_REQ_TITLE,
        "amount_found": $HAS_REQ_AMOUNT
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Safely copy to standard path
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "JSON Payload generated:"
cat /tmp/task_result.json
echo "=== Export Complete ==="