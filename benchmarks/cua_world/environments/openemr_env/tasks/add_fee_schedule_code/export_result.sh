#!/bin/bash
# Export script for Add Fee Schedule Code task

echo "=== Exporting Add Fee Schedule Code Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get the CPT4 type ID
CPT4_ID=$(cat /tmp/cpt4_type_id.txt 2>/dev/null || echo "1")

# Get initial counts
INITIAL_CPT_COUNT=$(cat /tmp/initial_cpt_count.txt 2>/dev/null || echo "0")
INITIAL_TOTAL_COUNT=$(cat /tmp/initial_total_codes.txt 2>/dev/null || echo "0")

# Get current counts
CURRENT_CPT_COUNT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e "SELECT COUNT(*) FROM codes WHERE code_type = $CPT4_ID" 2>/dev/null || echo "0")
CURRENT_TOTAL_COUNT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e "SELECT COUNT(*) FROM codes" 2>/dev/null || echo "0")

echo "Code counts: CPT4 initial=$INITIAL_CPT_COUNT current=$CURRENT_CPT_COUNT"
echo "Code counts: Total initial=$INITIAL_TOTAL_COUNT current=$CURRENT_TOTAL_COUNT"

# Query for the specific code 99441
echo ""
echo "=== Querying for code 99441 ==="
CODE_DATA=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e "
SELECT c.id, c.code, c.code_text, c.fee, c.code_type, ct.ct_key, c.active
FROM codes c
LEFT JOIN code_types ct ON c.code_type = ct.ct_id
WHERE c.code = '99441'
LIMIT 1
" 2>/dev/null)

echo "Raw query result: $CODE_DATA"

# Parse code data
CODE_FOUND="false"
CODE_ID=""
CODE_NUMBER=""
CODE_TEXT=""
CODE_FEE=""
CODE_TYPE_ID=""
CODE_TYPE_KEY=""
CODE_ACTIVE=""

if [ -n "$CODE_DATA" ]; then
    CODE_FOUND="true"
    CODE_ID=$(echo "$CODE_DATA" | cut -f1)
    CODE_NUMBER=$(echo "$CODE_DATA" | cut -f2)
    CODE_TEXT=$(echo "$CODE_DATA" | cut -f3)
    CODE_FEE=$(echo "$CODE_DATA" | cut -f4)
    CODE_TYPE_ID=$(echo "$CODE_DATA" | cut -f5)
    CODE_TYPE_KEY=$(echo "$CODE_DATA" | cut -f6)
    CODE_ACTIVE=$(echo "$CODE_DATA" | cut -f7)
    
    echo "Parsed data:"
    echo "  ID: $CODE_ID"
    echo "  Code: $CODE_NUMBER"
    echo "  Description: $CODE_TEXT"
    echo "  Fee: $CODE_FEE"
    echo "  Type ID: $CODE_TYPE_ID"
    echo "  Type Key: $CODE_TYPE_KEY"
    echo "  Active: $CODE_ACTIVE"
else
    echo "Code 99441 NOT found in database"
fi

# Check prices table as fallback for fee
PRICE_FROM_TABLE=""
if [ -n "$CODE_ID" ]; then
    PRICE_FROM_TABLE=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e "
    SELECT pr_price FROM prices WHERE pr_id = '$CODE_ID' LIMIT 1
    " 2>/dev/null || echo "")
    echo "Price from prices table: $PRICE_FROM_TABLE"
fi

# Validate code type is CPT4
CODE_TYPE_VALID="false"
if [ "$CODE_TYPE_KEY" = "CPT4" ] || [ "$CODE_TYPE_ID" = "$CPT4_ID" ]; then
    CODE_TYPE_VALID="true"
    echo "Code type is CPT4: valid"
else
    echo "Code type mismatch: expected CPT4 (id=$CPT4_ID), got $CODE_TYPE_KEY (id=$CODE_TYPE_ID)"
fi

# Validate description contains expected keywords
DESCRIPTION_VALID="false"
CODE_TEXT_UPPER=$(echo "$CODE_TEXT" | tr '[:lower:]' '[:upper:]')
HAS_TELEPHONE=$(echo "$CODE_TEXT_UPPER" | grep -qi "TELEPHONE\|PHONE" && echo "true" || echo "false")
HAS_EM=$(echo "$CODE_TEXT_UPPER" | grep -qiE "E/M|E&M|EVALUATION|MANAGEMENT" && echo "true" || echo "false")
if [ "$HAS_TELEPHONE" = "true" ] || [ "$HAS_EM" = "true" ]; then
    DESCRIPTION_VALID="true"
fi
echo "Description validation: telephone=$HAS_TELEPHONE, e/m=$HAS_EM, valid=$DESCRIPTION_VALID"

# Validate fee is approximately $45.00
FEE_VALID="false"
EFFECTIVE_FEE="$CODE_FEE"
if [ -z "$EFFECTIVE_FEE" ] || [ "$EFFECTIVE_FEE" = "NULL" ] || [ "$EFFECTIVE_FEE" = "0.00" ]; then
    EFFECTIVE_FEE="$PRICE_FROM_TABLE"
fi

if [ -n "$EFFECTIVE_FEE" ]; then
    # Remove any currency symbols and convert to number
    FEE_NUM=$(echo "$EFFECTIVE_FEE" | sed 's/[^0-9.]//g')
    if [ -n "$FEE_NUM" ]; then
        # Use bc for floating point comparison
        FEE_CHECK=$(echo "$FEE_NUM >= 44.50 && $FEE_NUM <= 45.50" | bc -l 2>/dev/null || echo "0")
        if [ "$FEE_CHECK" = "1" ]; then
            FEE_VALID="true"
            echo "Fee $FEE_NUM is within valid range (44.50-45.50)"
        else
            echo "Fee $FEE_NUM is outside valid range (44.50-45.50)"
        fi
    fi
fi

# Check if code was newly added (count increased)
NEWLY_ADDED="false"
if [ "$CURRENT_TOTAL_COUNT" -gt "$INITIAL_TOTAL_COUNT" ]; then
    NEWLY_ADDED="true"
    echo "New code(s) added: total increased from $INITIAL_TOTAL_COUNT to $CURRENT_TOTAL_COUNT"
fi

# Escape special characters for JSON
CODE_TEXT_ESCAPED=$(echo "$CODE_TEXT" | sed 's/"/\\"/g' | sed "s/'/\\\\'/g" | tr '\n' ' ')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/fee_schedule_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "cpt4_type_id": "$CPT4_ID",
    "initial_cpt_count": $INITIAL_CPT_COUNT,
    "current_cpt_count": $CURRENT_CPT_COUNT,
    "initial_total_count": $INITIAL_TOTAL_COUNT,
    "current_total_count": $CURRENT_TOTAL_COUNT,
    "code_found": $CODE_FOUND,
    "code": {
        "id": "$CODE_ID",
        "code_number": "$CODE_NUMBER",
        "code_text": "$CODE_TEXT_ESCAPED",
        "fee": "$CODE_FEE",
        "fee_from_prices_table": "$PRICE_FROM_TABLE",
        "effective_fee": "$EFFECTIVE_FEE",
        "code_type_id": "$CODE_TYPE_ID",
        "code_type_key": "$CODE_TYPE_KEY",
        "active": "$CODE_ACTIVE"
    },
    "validation": {
        "code_type_valid": $CODE_TYPE_VALID,
        "description_valid": $DESCRIPTION_VALID,
        "has_telephone_keyword": $HAS_TELEPHONE,
        "has_em_keyword": $HAS_EM,
        "fee_valid": $FEE_VALID,
        "newly_added": $NEWLY_ADDED
    },
    "screenshot_exists": $([ -f "/tmp/task_final.png" ] && echo "true" || echo "false")
}
EOF

# Move to final location
rm -f /tmp/fee_schedule_code_result.json 2>/dev/null || sudo rm -f /tmp/fee_schedule_code_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/fee_schedule_code_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/fee_schedule_code_result.json
chmod 666 /tmp/fee_schedule_code_result.json 2>/dev/null || sudo chmod 666 /tmp/fee_schedule_code_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/fee_schedule_code_result.json"
cat /tmp/fee_schedule_code_result.json
echo ""
echo "=== Export Complete ==="