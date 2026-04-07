#!/bin/bash
# Export script for Create Payroll Pay Codes task

echo "=== Exporting Create Payroll Pay Codes Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure Docker containers are running
if ! ensure_docker_containers; then
    echo "WARNING: Failed to ensure containers are running, database queries may fail."
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get task start timestamp
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Helper function for targeted queries
query_pay_code() {
    local field="$1"
    local name="$2"
    timetrex_query "SELECT $field FROM pay_code WHERE name ILIKE '$name' AND deleted=0 ORDER BY created_date DESC LIMIT 1" 2>/dev/null
}

echo "Querying database for created pay codes..."

# Query Hazmat Bonus
HAZMAT_ID=$(query_pay_code "id" "Hazmat Bonus")
HAZMAT_TYPE=$(query_pay_code "type_id" "Hazmat Bonus")
HAZMAT_DATE=$(query_pay_code "created_date" "Hazmat Bonus")

# Query Trainer Premium
TRAINER_ID=$(query_pay_code "id" "Trainer Premium")
TRAINER_TYPE=$(query_pay_code "type_id" "Trainer Premium")
TRAINER_DATE=$(query_pay_code "created_date" "Trainer Premium")

# Query Lost Equipment Fee
LOST_ID=$(query_pay_code "id" "Lost Equipment Fee")
LOST_TYPE=$(query_pay_code "type_id" "Lost Equipment Fee")
LOST_DATE=$(query_pay_code "created_date" "Lost Equipment Fee")

echo "Hazmat Bonus: ID=$HAZMAT_ID, Type=$HAZMAT_TYPE, Date=$HAZMAT_DATE"
echo "Trainer Premium: ID=$TRAINER_ID, Type=$TRAINER_TYPE, Date=$TRAINER_DATE"
echo "Lost Equipment Fee: ID=$LOST_ID, Type=$LOST_TYPE, Date=$LOST_DATE"

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/pay_codes_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "export_timestamp": $(date +%s),
    "hazmat_bonus": {
        "id": "$HAZMAT_ID",
        "type_id": "$HAZMAT_TYPE",
        "created_date": "$HAZMAT_DATE"
    },
    "trainer_premium": {
        "id": "$TRAINER_ID",
        "type_id": "$TRAINER_TYPE",
        "created_date": "$TRAINER_DATE"
    },
    "lost_equipment_fee": {
        "id": "$LOST_ID",
        "type_id": "$LOST_TYPE",
        "created_date": "$LOST_DATE"
    }
}
EOF

# Move to final location safely
rm -f /tmp/pay_codes_result.json 2>/dev/null || sudo rm -f /tmp/pay_codes_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/pay_codes_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/pay_codes_result.json
chmod 666 /tmp/pay_codes_result.json 2>/dev/null || sudo chmod 666 /tmp/pay_codes_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/pay_codes_result.json"
cat /tmp/pay_codes_result.json

echo ""
echo "=== Export Complete ==="