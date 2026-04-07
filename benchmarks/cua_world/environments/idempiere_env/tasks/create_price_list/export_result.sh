#!/bin/bash
set -e
echo "=== Exporting create_price_list results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_pricelist_count.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get Client ID
CLIENT_ID=$(get_gardenworld_client_id)

# ------------------------------------------------------------------
# Collect Data via Database Queries
# ------------------------------------------------------------------

# 1. Price List Details
PL_DATA=$(idempiere_query "
    SELECT m_pricelist_id, name, c_currency_id, issopricelist, priceprecision, EXTRACT(EPOCH FROM created)::bigint 
    FROM m_pricelist 
    WHERE name='2025 Spring Retail' AND ad_client_id=$CLIENT_ID AND isactive='Y' 
    LIMIT 1
" 2>/dev/null || echo "")

PL_EXISTS="false"
PL_ID=""
PL_NAME=""
PL_CURRENCY=""
PL_IS_SO="N"
PL_PRECISION=""
PL_CREATED="0"

if [ -n "$PL_DATA" ]; then
    PL_EXISTS="true"
    PL_ID=$(echo "$PL_DATA" | cut -d'|' -f1)
    PL_NAME=$(echo "$PL_DATA" | cut -d'|' -f2)
    CURRENCY_ID=$(echo "$PL_DATA" | cut -d'|' -f3)
    PL_IS_SO=$(echo "$PL_DATA" | cut -d'|' -f4)
    PL_PRECISION=$(echo "$PL_DATA" | cut -d'|' -f5)
    PL_CREATED=$(echo "$PL_DATA" | cut -d'|' -f6)
    
    # Resolve Currency ID to ISO code
    if [ -n "$CURRENCY_ID" ]; then
        PL_CURRENCY=$(idempiere_query "SELECT iso_code FROM c_currency WHERE c_currency_id=$CURRENCY_ID" 2>/dev/null || echo "")
    fi
fi

# 2. Version Details
VER_EXISTS="false"
VER_ID=""
VER_NAME=""
VER_VALID_FROM=""

if [ "$PL_EXISTS" = "true" ]; then
    VER_DATA=$(idempiere_query "
        SELECT m_pricelist_version_id, name, to_char(validfrom, 'YYYY-MM-DD') 
        FROM m_pricelist_version 
        WHERE m_pricelist_id=$PL_ID AND isactive='Y' 
        ORDER BY created DESC LIMIT 1
    " 2>/dev/null || echo "")
    
    if [ -n "$VER_DATA" ]; then
        VER_EXISTS="true"
        VER_ID=$(echo "$VER_DATA" | cut -d'|' -f1)
        VER_NAME=$(echo "$VER_DATA" | cut -d'|' -f2)
        VER_VALID_FROM=$(echo "$VER_DATA" | cut -d'|' -f3)
    fi
fi

# 3. Product Prices
# We need to query prices for Azalea Bush, Elm Tree, Oak Tree
PROD_JSON=""

if [ "$VER_EXISTS" = "true" ]; then
    # Helper to build JSON object for a product
    get_prod_price() {
        local pname="$1"
        local pdata
        pdata=$(idempiere_query "
            SELECT pp.pricelist, pp.pricestd, pp.pricelimit 
            FROM m_productprice pp
            JOIN m_product p ON pp.m_product_id = p.m_product_id
            WHERE pp.m_pricelist_version_id=$VER_ID 
              AND p.name ILIKE '%${pname}%'
            LIMIT 1
        " 2>/dev/null || echo "")
        
        if [ -n "$pdata" ]; then
            local plist=$(echo "$pdata" | cut -d'|' -f1)
            local pstd=$(echo "$pdata" | cut -d'|' -f2)
            local plimit=$(echo "$pdata" | cut -d'|' -f3)
            echo "{\"name\": \"$pname\", \"found\": true, \"list\": $plist, \"std\": $pstd, \"limit\": $plimit}"
        else
            echo "{\"name\": \"$pname\", \"found\": false}"
        fi
    }
    
    P1=$(get_prod_price "Azalea Bush")
    P2=$(get_prod_price "Elm Tree")
    P3=$(get_prod_price "Oak Tree")
    PROD_JSON="[$P1, $P2, $P3]"
else
    PROD_JSON="[]"
fi

# 4. Current Price List Count
CURRENT_COUNT=$(idempiere_query "SELECT COUNT(*) FROM m_pricelist WHERE ad_client_id=$CLIENT_ID AND isactive='Y'" 2>/dev/null || echo "0")

# 5. Construct Result JSON
# Using a temp file and simple concatenation to avoid complex jq dependencies if possible, 
# but python is safer for JSON generation.
python3 -c "
import json
import os

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'initial_count': int('$INITIAL_COUNT'),
    'current_count': int('$CURRENT_COUNT'),
    'price_list': {
        'exists': $PL_EXISTS,
        'name': '$PL_NAME',
        'currency': '$PL_CURRENCY',
        'is_so': '$PL_IS_SO',
        'precision': '$PL_PRECISION',
        'created_ts': $PL_CREATED
    },
    'version': {
        'exists': $VER_EXISTS,
        'name': '$VER_NAME',
        'valid_from': '$VER_VALID_FROM'
    },
    'products': $PROD_JSON,
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="