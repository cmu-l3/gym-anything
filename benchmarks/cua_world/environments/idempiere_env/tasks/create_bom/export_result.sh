#!/bin/bash
set -e
echo "=== Exporting BOM Creation Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Gather Task Data
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_BOM_COUNT=$(cat /tmp/initial_bom_count.txt 2>/dev/null || echo "0")
CLIENT_ID=$(get_gardenworld_client_id)
if [ -z "$CLIENT_ID" ]; then CLIENT_ID="11"; fi

# 3. Query Database for Result Verification

# Get the created BOM (if any)
BOM_QUERY="SELECT pp_product_bom_id, value, name, m_product_id, isactive, created FROM pp_product_bom WHERE value='PS-BOM-2024' AND ad_client_id=$CLIENT_ID"
BOM_DATA=$(idempiere_query "$BOM_QUERY" 2>/dev/null || echo "")

# Parse BOM Data
BOM_EXISTS="false"
BOM_ID=""
BOM_VALUE=""
BOM_NAME=""
BOM_PRODUCT_ID=""
BOM_ACTIVE=""
BOM_CREATED=""

if [ -n "$BOM_DATA" ]; then
    BOM_EXISTS="true"
    # Postgres output format depends on configuration, assuming default pipe/tab separation or simple string for single column
    # The helper `idempiere_query` uses `psql -t -A`, so fields are pipe-separated by default if multiple columns selected
    # But wait, `psql -A` uses unaligned output, usually pipe separated. Let's make sure.
    # We will fetch fields individually to be safer or use a specific separator.
    
    BOM_ID=$(idempiere_query "SELECT pp_product_bom_id FROM pp_product_bom WHERE value='PS-BOM-2024' AND ad_client_id=$CLIENT_ID" 2>/dev/null)
    BOM_VALUE=$(idempiere_query "SELECT value FROM pp_product_bom WHERE pp_product_bom_id=$BOM_ID" 2>/dev/null)
    BOM_NAME=$(idempiere_query "SELECT name FROM pp_product_bom WHERE pp_product_bom_id=$BOM_ID" 2>/dev/null)
    BOM_PRODUCT_ID=$(idempiere_query "SELECT m_product_id FROM pp_product_bom WHERE pp_product_bom_id=$BOM_ID" 2>/dev/null)
    BOM_ACTIVE=$(idempiere_query "SELECT isactive FROM pp_product_bom WHERE pp_product_bom_id=$BOM_ID" 2>/dev/null)
    BOM_CREATED_EPOCH=$(idempiere_query "SELECT EXTRACT(EPOCH FROM created)::integer FROM pp_product_bom WHERE pp_product_bom_id=$BOM_ID" 2>/dev/null)
fi

# Get Parent Product Name
PARENT_PRODUCT_NAME=""
if [ -n "$BOM_PRODUCT_ID" ]; then
    PARENT_PRODUCT_NAME=$(idempiere_query "SELECT name FROM m_product WHERE m_product_id=$BOM_PRODUCT_ID" 2>/dev/null)
fi

# Get BOM Lines
LINES_JSON="[]"
if [ -n "$BOM_ID" ]; then
    # Construct a JSON array of lines manually or effectively
    # Format: ProductID|ProductName|Qty|IsActive
    LINES_RAW=$(idempiere_query "SELECT bl.m_product_id, p.name, bl.qtybom, bl.isactive FROM pp_product_bomline bl JOIN m_product p ON bl.m_product_id=p.m_product_id WHERE bl.pp_product_bom_id=$BOM_ID" 2>/dev/null)
    
    # Process lines into JSON
    if [ -n "$LINES_RAW" ]; then
        LINES_JSON="["
        FIRST="true"
        while IFS='|' read -r pid pname qty active; do
            if [ "$FIRST" = "true" ]; then FIRST="false"; else LINES_JSON="$LINES_JSON,"; fi
            # Sanitize strings
            pname_clean=$(echo "$pname" | sed 's/"/\\"/g')
            LINES_JSON="$LINES_JSON {\"product_id\": \"$pid\", \"product_name\": \"$pname_clean\", \"qty\": \"$qty\", \"isactive\": \"$active\"}"
        done <<< "$LINES_RAW"
        LINES_JSON="$LINES_JSON]"
    fi
fi

# Get Current Counts
CURRENT_BOM_COUNT=$(idempiere_query "SELECT COUNT(*) FROM pp_product_bom WHERE ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")

# 4. Construct Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "initial_bom_count": $INITIAL_BOM_COUNT,
    "current_bom_count": $CURRENT_BOM_COUNT,
    "bom_exists": $BOM_EXISTS,
    "bom_details": {
        "id": "$BOM_ID",
        "value": "$BOM_VALUE",
        "name": "$BOM_NAME",
        "parent_product_id": "$BOM_PRODUCT_ID",
        "parent_product_name": "$PARENT_PRODUCT_NAME",
        "isactive": "$BOM_ACTIVE",
        "created_epoch": "${BOM_CREATED_EPOCH:-0}"
    },
    "bom_lines": $LINES_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 5. Save to shared location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="