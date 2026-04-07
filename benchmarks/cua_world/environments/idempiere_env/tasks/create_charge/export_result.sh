#!/bin/bash
set -e
echo "=== Exporting create_charge result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Data to collect
CLIENT_ID=$(get_gardenworld_client_id)
if [ -z "$CLIENT_ID" ]; then CLIENT_ID=11; fi

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_charge_count.txt 2>/dev/null || echo "0")

# 1. Check if record exists and fetch details
CHARGE_EXISTS="false"
CHARGE_DATA="{}"

# Query columns: name, chargeamt, description, isactive, c_taxcategory_id, created
# We look specifically for the Search Key 'WTF-001'
# Note: idempiere_query uses '|' as separator
RAW_DATA=$(idempiere_query "SELECT name, chargeamt, description, isactive, c_taxcategory_id, EXTRACT(EPOCH FROM created)::bigint FROM c_charge WHERE value='WTF-001' AND ad_client_id=$CLIENT_ID" 2>/dev/null || echo "")

if [ -n "$RAW_DATA" ]; then
    CHARGE_EXISTS="true"
    echo "Charge record found: $RAW_DATA"
    
    # Parse pipe-separated values
    IFS='|' read -r NAME AMT DESC ACTIVE TAX_ID CREATED_TS <<< "$RAW_DATA"
    
    # Get Tax Category Name if ID exists
    TAX_NAME=""
    if [ -n "$TAX_ID" ] && [ "$TAX_ID" != "" ]; then
        TAX_NAME=$(idempiere_query "SELECT name FROM c_taxcategory WHERE c_taxcategory_id=$TAX_ID" 2>/dev/null || echo "")
    fi
    
    # Clean up strings for JSON (escape quotes)
    NAME_JSON=$(echo "$NAME" | sed 's/"/\\"/g')
    DESC_JSON=$(echo "$DESC" | sed 's/"/\\"/g')
    TAX_NAME_JSON=$(echo "$TAX_NAME" | sed 's/"/\\"/g')
    
    CHARGE_DATA="{
        \"name\": \"$NAME_JSON\",
        \"amount\": \"$AMT\",
        \"description\": \"$DESC_JSON\",
        \"is_active\": \"$ACTIVE\",
        \"tax_category\": \"$TAX_NAME_JSON\",
        \"created_ts\": ${CREATED_TS:-0}
    }"
else
    echo "Charge record NOT found with value 'WTF-001'"
fi

# Get final count
FINAL_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_charge WHERE ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "initial_count": $INITIAL_COUNT,
    "final_count": $FINAL_COUNT,
    "charge_exists": $CHARGE_EXISTS,
    "charge_data": $CHARGE_DATA
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="