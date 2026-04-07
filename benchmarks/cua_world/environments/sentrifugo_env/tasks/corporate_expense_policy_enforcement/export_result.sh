#!/bin/bash
echo "=== Exporting Corporate Expense Policy Result ==="

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Extract database state for expenses
# We dump the tables to text files so the verifier can parse them flexibly
docker exec sentrifugo-db mysql -u sentrifugo -psentrifugo123 sentrifugo -e "SELECT * FROM main_expensecategories;" > /tmp/expense_categories_dump.txt 2>/dev/null || echo "TABLE_NOT_FOUND" > /tmp/expense_categories_dump.txt

# Try to find the expense claims table (could be main_expenses or main_expenserequests)
EXPENSES_TABLE=$(docker exec sentrifugo-db mysql -u sentrifugo -psentrifugo123 sentrifugo -N -e "SELECT table_name FROM information_schema.tables WHERE table_schema='sentrifugo' AND table_name LIKE '%expense%' AND table_name NOT LIKE '%categor%';" | head -1)

if [ -n "$EXPENSES_TABLE" ]; then
    docker exec sentrifugo-db mysql -u sentrifugo -psentrifugo123 sentrifugo -e "SELECT * FROM $EXPENSES_TABLE;" > /tmp/expense_claims_dump.txt 2>/dev/null || echo "ERROR_READING_TABLE" > /tmp/expense_claims_dump.txt
else
    echo "TABLE_NOT_FOUND" > /tmp/expense_claims_dump.txt
fi

# 3. Format result JSON
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

TEMP_JSON=$(mktemp /tmp/expense_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "categories_dump_path": "/tmp/expense_categories_dump.txt",
    "claims_dump_path": "/tmp/expense_claims_dump.txt",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions so the verifier can read it
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
chmod 666 /tmp/expense_categories_dump.txt 2>/dev/null || true
chmod 666 /tmp/expense_claims_dump.txt 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="