#!/bin/bash
echo "=== Exporting Task Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CLIENT_ID=$(get_gardenworld_client_id)

# 1. Query the New Category
echo "Checking for new category 'OUTDOOR-FURN'..."
CATEGORY_JSON=$(idempiere_query "
SELECT row_to_json(t) FROM (
    SELECT 
        m_product_category_id,
        value as search_key, 
        name, 
        mmpolicy, 
        plannedmargin, 
        created, 
        updated 
    FROM m_product_category 
    WHERE value='OUTDOOR-FURN' AND ad_client_id=$CLIENT_ID
) t
" 2>/dev/null || echo "{}")

# If empty (no record found), set to null/empty object
if [ -z "$CATEGORY_JSON" ]; then
    CATEGORY_JSON="null"
fi

# 2. Query the Product 'Patio Chair'
echo "Checking product 'Patio Chair'..."
PRODUCT_JSON=$(idempiere_query "
SELECT row_to_json(t) FROM (
    SELECT 
        m_product_id,
        name, 
        m_product_category_id, 
        updated 
    FROM m_product 
    WHERE name='Patio Chair' AND ad_client_id=$CLIENT_ID
) t
" 2>/dev/null || echo "{}")

if [ -z "$PRODUCT_JSON" ]; then
    PRODUCT_JSON="null"
fi

# 3. Get Initial State for comparison
INITIAL_CAT_ID=$(cat /tmp/initial_product_cat_id.txt 2>/dev/null || echo "0")

# 4. Check for 'Standard' category ID for reference (to ensure we actually moved away from it)
STD_CAT_ID=$(idempiere_query "SELECT m_product_category_id FROM m_product_category WHERE name='Standard' AND ad_client_id=$CLIENT_ID LIMIT 1" 2>/dev/null || echo "0")

# 5. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 6. Construct Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "initial_product_cat_id": "$INITIAL_CAT_ID",
    "standard_cat_id": "$STD_CAT_ID",
    "category_record": $CATEGORY_JSON,
    "product_record": $PRODUCT_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="