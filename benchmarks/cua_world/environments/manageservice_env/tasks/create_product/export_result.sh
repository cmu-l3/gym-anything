#!/bin/bash
echo "=== Exporting Create Product results ==="
source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Get Task Start Time
START_TIME_MS=$(cat /tmp/task_start_time_ms.txt 2>/dev/null || echo "0")

# 1. Check Product Type
# Try 'name' column first, then 'typename' (schema varies by version)
PT_DATA=$(sdp_db_exec "SELECT producttypeid, name FROM producttype WHERE name ILIKE 'Network Switch' LIMIT 1" 2>/dev/null)
if [ -z "$PT_DATA" ]; then
    PT_DATA=$(sdp_db_exec "SELECT producttypeid, typename FROM producttype WHERE typename ILIKE 'Network Switch' LIMIT 1" 2>/dev/null)
fi

PT_EXISTS="false"
PT_ID=""
PT_NAME=""

if [ -n "$PT_DATA" ]; then
    PT_EXISTS="true"
    # Parse pipe-separated output (e.g. "101|Network Switch")
    PT_ID=$(echo "$PT_DATA" | cut -d'|' -f1)
    PT_NAME=$(echo "$PT_DATA" | cut -d'|' -f2)
fi

# 2. Check Product
# Table 'product'. Columns: productid, productname, producttypeid, manufacturerid
PROD_DATA=$(sdp_db_exec "SELECT productid, productname, producttypeid, manufacturerid FROM product WHERE productname ILIKE '%Cisco Catalyst 9200L-24P-4G%' LIMIT 1" 2>/dev/null)

PROD_EXISTS="false"
PROD_ID=""
PROD_NAME=""
PROD_PT_ID=""
PROD_MFR_ID=""

if [ -n "$PROD_DATA" ]; then
    PROD_EXISTS="true"
    PROD_ID=$(echo "$PROD_DATA" | cut -d'|' -f1)
    PROD_NAME=$(echo "$PROD_DATA" | cut -d'|' -f2)
    PROD_PT_ID=$(echo "$PROD_DATA" | cut -d'|' -f3)
    PROD_MFR_ID=$(echo "$PROD_DATA" | cut -d'|' -f4)
fi

# 3. Check Manufacturer Name
MFR_NAME=""
if [ -n "$PROD_MFR_ID" ] && [ "$PROD_MFR_ID" != "0" ] && [ "$PROD_MFR_ID" != "" ]; then
    # Try 'name' then 'manufacturername'
    MFR_DATA=$(sdp_db_exec "SELECT name FROM manufacturer WHERE manufacturerid = $PROD_MFR_ID" 2>/dev/null)
    if [ -z "$MFR_DATA" ]; then
         MFR_DATA=$(sdp_db_exec "SELECT manufacturername FROM manufacturer WHERE manufacturerid = $PROD_MFR_ID" 2>/dev/null)
    fi
    MFR_NAME="$MFR_DATA"
fi

# Use Python to generate clean JSON
python3 -c "
import json
result = {
    'product_type_exists': $PT_EXISTS,
    'product_type_id': '$PT_ID',
    'product_type_name': '''$PT_NAME'''.strip(),
    'product_exists': $PROD_EXISTS,
    'product_id': '$PROD_ID',
    'product_name': '''$PROD_NAME'''.strip(),
    'linked_product_type_id': '$PROD_PT_ID',
    'manufacturer_name': '''$MFR_NAME'''.strip(),
    'manufacturer_id': '$PROD_MFR_ID',
    'start_time_ms': $START_TIME_MS
}
print(json.dumps(result))
" > /tmp/task_result.json

chmod 666 /tmp/task_result.json
echo "Export done."
cat /tmp/task_result.json