#!/bin/bash
echo "=== Exporting create_warehouse task result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Query Warehouse Data
echo "--- Querying Warehouse Data ---"
# Get JSON-like output using psql's formatting or manual construction
# We will fetch fields and construct JSON manually to be robust against psql versions

WH_DATA=$(idempiere_query "SELECT m_warehouse_id, name, isactive, ad_org_id, created FROM m_warehouse WHERE value='GW-WDC'")

WH_FOUND="false"
WH_ID=""
WH_NAME=""
WH_ACTIVE=""
WH_ORG=""
WH_CREATED=""

if [ -n "$WH_DATA" ]; then
    WH_FOUND="true"
    WH_ID=$(echo "$WH_DATA" | cut -d'|' -f1)
    WH_NAME=$(echo "$WH_DATA" | cut -d'|' -f2)
    WH_ACTIVE=$(echo "$WH_DATA" | cut -d'|' -f3)
    WH_ORG=$(echo "$WH_DATA" | cut -d'|' -f4)
    WH_CREATED=$(echo "$WH_DATA" | cut -d'|' -f5)
fi

# 3. Query Locator Data if warehouse exists
LOCATORS_JSON="[]"
if [ -n "$WH_ID" ]; then
    # Fetch locators: value, x, y, z, isdefault
    # Note: Using a separator that is unlikely to be in user input, e.g., '|||'
    LOC_ROWS=$(docker exec idempiere-postgres psql -U adempiere -d idempiere -t -A -F "|||" -c "SELECT value, x, y, z, isdefault, created FROM m_locator WHERE m_warehouse_id=$WH_ID ORDER BY value")
    
    # Convert rows to JSON array
    if [ -n "$LOC_ROWS" ]; then
        LOCATORS_JSON="["
        FIRST=true
        while IFS= read -r line; do
            if [ "$FIRST" = true ]; then FIRST=false; else LOCATORS_JSON="$LOCATORS_JSON,"; fi
            
            VAL=$(echo "$line" | awk -F '|||' '{print $1}')
            X=$(echo "$line" | awk -F '|||' '{print $2}')
            Y=$(echo "$line" | awk -F '|||' '{print $3}')
            Z=$(echo "$line" | awk -F '|||' '{print $4}')
            DEF=$(echo "$line" | awk -F '|||' '{print $5}')
            CREATED=$(echo "$line" | awk -F '|||' '{print $6}')
            
            # Simple JSON construction
            LOCATORS_JSON="$LOCATORS_JSON {\"value\": \"$VAL\", \"x\": \"$X\", \"y\": \"$Y\", \"z\": \"$Z\", \"is_default\": \"$DEF\", \"created\": \"$CREATED\"}"
        done <<< "$LOC_ROWS"
        LOCATORS_JSON="$LOCATORS_JSON]"
    fi
fi

# 4. Construct Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": "$TASK_START",
    "warehouse": {
        "found": $WH_FOUND,
        "name": "$WH_NAME",
        "is_active": "$WH_ACTIVE",
        "org_id": "$WH_ORG",
        "created_timestamp": "$WH_CREATED"
    },
    "locators": $LOCATORS_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 5. Save to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="