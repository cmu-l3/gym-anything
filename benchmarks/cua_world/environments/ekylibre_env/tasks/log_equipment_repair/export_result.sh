#!/bin/bash
set -e
echo "=== Exporting results for: log_equipment_repair@1 ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Get task start time
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Query the database for the new intervention
# We look for interventions created AFTER the start time.
# We join with products to get the target equipment name.
# We join with product natures to confirm it is a tractor/equipment.

echo "Querying database for new interventions..."

# SQL query to get details of the most recent intervention created during the task
# Output format: ID|NATURE|DESCRIPTION|AMOUNT|TARGET_NAME|TARGET_NATURE
SQL_QUERY="
SELECT 
    i.id, 
    i.nature, 
    i.description, 
    i.pretax_amount, 
    p.name, 
    pn.name 
FROM interventions i
LEFT JOIN products p ON (i.target_type = 'Product' AND i.target_id = p.id)
LEFT JOIN product_nature_variants pnv ON p.product_nature_variant_id = pnv.id
LEFT JOIN product_natures pn ON pnv.product_nature_id = pn.id
WHERE i.created_at >= to_timestamp($START_TIME)
ORDER BY i.created_at DESC
LIMIT 1;
"

# Execute query via docker
DB_RESULT=$(docker exec ekylibre-db psql -U ekylibre -d ekylibre_production -t -A -F "|" -c "$SQL_QUERY" 2>/dev/null || echo "")

# 4. Parse result into JSON
# Default values
FOUND="false"
INT_ID=""
NATURE=""
DESCRIPTION=""
AMOUNT="0.0"
TARGET_NAME=""
TARGET_NATURE=""

if [ -n "$DB_RESULT" ]; then
    FOUND="true"
    INT_ID=$(echo "$DB_RESULT" | cut -d'|' -f1)
    NATURE=$(echo "$DB_RESULT" | cut -d'|' -f2)
    DESCRIPTION=$(echo "$DB_RESULT" | cut -d'|' -f3)
    AMOUNT=$(echo "$DB_RESULT" | cut -d'|' -f4)
    TARGET_NAME=$(echo "$DB_RESULT" | cut -d'|' -f5)
    TARGET_NATURE=$(echo "$DB_RESULT" | cut -d'|' -f6)
fi

# Get counts
INITIAL_COUNT=$(cat /tmp/initial_count.txt 2>/dev/null || echo "0")
FINAL_COUNT=$(ekylibre_db_query "SELECT count(*) FROM interventions")

# Prepare JSON output
# We use a temp file to avoid permission issues, then move it
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# Escape quotes in description/names for JSON safety (basic)
DESCRIPTION_SAFE=$(echo "$DESCRIPTION" | sed 's/"/\\"/g' | sed 's/|/ /g')
TARGET_NAME_SAFE=$(echo "$TARGET_NAME" | sed 's/"/\\"/g')

cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $START_TIME,
    "intervention_found": $FOUND,
    "intervention": {
        "id": "$INT_ID",
        "nature": "$NATURE",
        "description": "$DESCRIPTION_SAFE",
        "amount": "$AMOUNT",
        "target_name": "$TARGET_NAME_SAFE",
        "target_nature": "$TARGET_NATURE"
    },
    "counts": {
        "initial": ${INITIAL_COUNT:-0},
        "final": ${FINAL_COUNT:-0}
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with lenient permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json