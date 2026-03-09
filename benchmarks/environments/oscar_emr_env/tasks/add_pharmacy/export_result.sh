#!/bin/bash
# Export script for Add Pharmacy task
# Queries the Oscar database for the new pharmacy record and exports to JSON

echo "=== Exporting Add Pharmacy Result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# 2. Get initial count and start time
INITIAL_COUNT=$(cat /tmp/initial_pharmacy_count 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 3. Query for the specific pharmacy
# We search by name pattern to be robust against minor typos in "Inc" or similar
echo "Searching for pharmacy record..."
QUERY="SELECT ID, name, address, city, province, postalCode, phone1, fax, email, lastUpdateDate FROM pharmacyInfo WHERE name LIKE '%Lakeshore%Compounding%' ORDER BY ID DESC LIMIT 1"

PHARMACY_DATA=$(oscar_query "$QUERY" 2>/dev/null)

FOUND="false"
PHARMACY_JSON="{}"

if [ -n "$PHARMACY_DATA" ]; then
    FOUND="true"
    echo "Pharmacy record found."
    
    # Parse tab-separated output
    # Note: oscar_query uses -N (no headers), so columns match the SELECT order
    P_ID=$(echo "$PHARMACY_DATA" | cut -f1)
    P_NAME=$(echo "$PHARMACY_DATA" | cut -f2)
    P_ADDR=$(echo "$PHARMACY_DATA" | cut -f3)
    P_CITY=$(echo "$PHARMACY_DATA" | cut -f4)
    P_PROV=$(echo "$PHARMACY_DATA" | cut -f5)
    P_POSTAL=$(echo "$PHARMACY_DATA" | cut -f6)
    P_PHONE=$(echo "$PHARMACY_DATA" | cut -f7)
    P_FAX=$(echo "$PHARMACY_DATA" | cut -f8)
    P_EMAIL=$(echo "$PHARMACY_DATA" | cut -f9)
    # Date formatting might vary, pass as string
    P_DATE=$(echo "$PHARMACY_DATA" | cut -f10)

    # Escape quotes for JSON
    P_NAME=$(echo "$P_NAME" | sed 's/"/\\"/g')
    P_ADDR=$(echo "$P_ADDR" | sed 's/"/\\"/g')
    
    # Construct JSON object for the record
    PHARMACY_JSON="{
        \"id\": \"$P_ID\",
        \"name\": \"$P_NAME\",
        \"address\": \"$P_ADDR\",
        \"city\": \"$P_CITY\",
        \"province\": \"$P_PROV\",
        \"postal\": \"$P_POSTAL\",
        \"phone\": \"$P_PHONE\",
        \"fax\": \"$P_FAX\",
        \"email\": \"$P_EMAIL\",
        \"last_update\": \"$P_DATE\"
    }"
else
    echo "No pharmacy record found matching 'Lakeshore Compounding'."
fi

# 4. Get current total count
CURRENT_COUNT=$(oscar_query "SELECT COUNT(*) FROM pharmacyInfo" || echo "0")

# 5. Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "found": $FOUND,
    "pharmacy": $PHARMACY_JSON,
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "task_start_timestamp": $TASK_START,
    "export_timestamp": $(date +%s)
}
EOF

# 6. Save to final location (handle permissions)
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="