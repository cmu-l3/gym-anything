#!/bin/bash
echo "=== Exporting register_supplier_credit_note results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_purchase_count.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Query the database for the specific credit note by reference number
# We look for 'AV-2025-004'. We join with entities to get supplier name.
# We fetch: id, type, supplier_name, pretax_amount, invoiced_at, created_at
QUERY="
SELECT 
    p.id, 
    p.type, 
    e.name as supplier_name, 
    p.pretax_amount, 
    p.invoiced_at, 
    EXTRACT(EPOCH FROM p.created_at) as created_ts
FROM purchases p
LEFT JOIN entities e ON p.supplier_id = e.id
WHERE p.reference_number = 'AV-2025-004'
ORDER BY p.created_at DESC 
LIMIT 1;
"

# Execute query inside docker container
DB_RESULT=$(docker exec ekylibre-db psql -U ekylibre -d ekylibre_production -t -A -F "|" -c "$QUERY" 2>/dev/null || echo "")

# Parse result
RECORD_FOUND="false"
RECORD_ID=""
RECORD_TYPE=""
SUPPLIER_NAME=""
PRETAX_AMOUNT="0"
INVOICED_DATE=""
CREATED_TS="0"

if [ -n "$DB_RESULT" ]; then
    RECORD_FOUND="true"
    RECORD_ID=$(echo "$DB_RESULT" | cut -d'|' -f1)
    RECORD_TYPE=$(echo "$DB_RESULT" | cut -d'|' -f2)
    SUPPLIER_NAME=$(echo "$DB_RESULT" | cut -d'|' -f3)
    PRETAX_AMOUNT=$(echo "$DB_RESULT" | cut -d'|' -f4)
    INVOICED_DATE=$(echo "$DB_RESULT" | cut -d'|' -f5)
    CREATED_TS=$(echo "$DB_RESULT" | cut -d'|' -f6 | cut -d'.' -f1)
fi

# 2. Get current total count
CURRENT_COUNT=$(docker exec ekylibre-db psql -U ekylibre -d ekylibre_production -t -A -c "SELECT COUNT(*) FROM purchases;" 2>/dev/null || echo "0")

# 3. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "record_found": $RECORD_FOUND,
    "record_details": {
        "id": "$RECORD_ID",
        "type": "$RECORD_TYPE",
        "supplier_name": "$SUPPLIER_NAME",
        "pretax_amount": "$PRETAX_AMOUNT",
        "invoiced_date": "$INVOICED_DATE",
        "created_timestamp": $CREATED_TS
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="