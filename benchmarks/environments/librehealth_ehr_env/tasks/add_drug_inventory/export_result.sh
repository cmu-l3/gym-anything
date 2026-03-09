#!/bin/bash
echo "=== Exporting add_drug_inventory results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_drug_count.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query the database for the added drug
# We look for the most recently added drug that matches 'Metformin'
echo "Querying database for results..."

# 1. Get current total count
FINAL_COUNT=$(docker exec librehealth-db mysql -u libreehr -ps3cret libreehr -N -e \
    "SELECT COUNT(*) FROM drugs" 2>/dev/null || echo "0")

# 2. Get details of the Metformin record (if any)
# We fetch specific fields: name, ndc_number, form, route, size, unit
# We use JSON_OBJECT if available, or manual construction if MariaDB version is old
# Since we can't rely on JSON functions in all containers, we export to a temp file then parse

QUERY="SELECT name, ndc_number, form, route, size, unit FROM drugs WHERE LOWER(name) LIKE '%metformin%' ORDER BY drug_id DESC LIMIT 1"

# Execute query and capture output (tab separated)
RESULT_ROW=$(docker exec librehealth-db mysql -u libreehr -ps3cret libreehr -N -e "$QUERY" 2>/dev/null || echo "")

# Parse the result row (handling potentially empty results)
DRUG_FOUND="false"
DRUG_NAME=""
DRUG_NDC=""
DRUG_FORM="0"
DRUG_ROUTE="0"
DRUG_SIZE="0"
DRUG_UNIT="0"

if [ -n "$RESULT_ROW" ]; then
    DRUG_FOUND="true"
    DRUG_NAME=$(echo "$RESULT_ROW" | awk -F'\t' '{print $1}')
    DRUG_NDC=$(echo "$RESULT_ROW" | awk -F'\t' '{print $2}')
    DRUG_FORM=$(echo "$RESULT_ROW" | awk -F'\t' '{print $3}')
    DRUG_ROUTE=$(echo "$RESULT_ROW" | awk -F'\t' '{print $4}')
    DRUG_SIZE=$(echo "$RESULT_ROW" | awk -F'\t' '{print $5}')
    DRUG_UNIT=$(echo "$RESULT_ROW" | awk -F'\t' '{print $6}')
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": $INITIAL_COUNT,
    "final_count": $FINAL_COUNT,
    "drug_found": $DRUG_FOUND,
    "drug_name": "$(echo $DRUG_NAME | sed 's/"/\\"/g')",
    "drug_ndc": "$(echo $DRUG_NDC | sed 's/"/\\"/g')",
    "drug_form": "$DRUG_FORM",
    "drug_route": "$DRUG_ROUTE",
    "drug_size": "$DRUG_SIZE",
    "drug_unit": "$DRUG_UNIT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="