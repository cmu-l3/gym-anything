#!/bin/bash
echo "=== Exporting create_uom_conversion results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CLIENT_ID=$(get_gardenworld_client_id)

# 1. Check for UOM 'BX24'
echo "Checking for UOM 'BX24'..."
UOM_DATA=$(idempiere_query "SELECT c_uom_id, name, stdprecision, isactive, created FROM c_uom WHERE uomsymbol='BX24' AND ad_client_id=$CLIENT_ID ORDER BY created DESC LIMIT 1")

UOM_EXISTS="false"
UOM_ID=""
UOM_NAME=""
UOM_PRECISION=""
UOM_CREATED=""

if [ -n "$UOM_DATA" ]; then
    UOM_EXISTS="true"
    UOM_ID=$(echo "$UOM_DATA" | cut -d'|' -f1)
    UOM_NAME=$(echo "$UOM_DATA" | cut -d'|' -f2)
    UOM_PRECISION=$(echo "$UOM_DATA" | cut -d'|' -f3)
    # isactive is f4
    UOM_CREATED=$(echo "$UOM_DATA" | cut -d'|' -f5)
fi

# 2. Check for Conversion (only if UOM exists)
CONV_EXISTS="false"
CONV_RATE="0"
CONV_GLOBAL="false"

if [ "$UOM_EXISTS" = "true" ]; then
    echo "Checking conversion for UOM ID $UOM_ID..."
    # We look for a conversion to 'Each' (Symbol usually EA or Each)
    # We select multiplyrate and whether m_product_id is null
    CONV_DATA=$(idempiere_query "SELECT multiplyrate, m_product_id FROM c_uom_conversion WHERE c_uom_id=$UOM_ID AND isactive='Y' ORDER BY created DESC LIMIT 1")
    
    if [ -n "$CONV_DATA" ]; then
        CONV_EXISTS="true"
        CONV_RATE=$(echo "$CONV_DATA" | cut -d'|' -f1)
        PRODUCT_ID=$(echo "$CONV_DATA" | cut -d'|' -f2)
        
        # In iDempiere database, NULL often comes back as empty string in psql -A -t output
        if [ -z "$PRODUCT_ID" ]; then
            CONV_GLOBAL="true"
        else
            CONV_GLOBAL="false"
        fi
    fi
fi

# 3. Take final screenshot
take_screenshot /tmp/task_final.png

# 4. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "uom_exists": $UOM_EXISTS,
    "uom_name": "$UOM_NAME",
    "uom_precision": "$UOM_PRECISION",
    "uom_created_timestamp": "$UOM_CREATED",
    "conversion_exists": $CONV_EXISTS,
    "conversion_rate": $CONV_RATE,
    "conversion_is_global": $CONV_GLOBAL,
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