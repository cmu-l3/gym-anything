#!/bin/bash
# Export script for Search Relevance Configuration task

echo "=== Exporting Search Relevance Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 1. Get Final State (Search Weights)
echo "Querying final search weights..."
QUERY="SELECT ea.attribute_code, cea.search_weight 
       FROM eav_attribute ea 
       JOIN catalog_eav_attribute cea ON ea.attribute_id = cea.attribute_id 
       WHERE ea.entity_type_id = 4 
       AND ea.attribute_code IN ('sku', 'name', 'description');"

FINAL_STATE_RAW=$(magento_query "$QUERY" 2>/dev/null)

# Parse the output into variables
# Expected format: attribute_code \t search_weight
SKU_WEIGHT=$(echo "$FINAL_STATE_RAW" | grep "^sku" | awk '{print $2}')
NAME_WEIGHT=$(echo "$FINAL_STATE_RAW" | grep "^name" | awk '{print $2}')
DESC_WEIGHT=$(echo "$FINAL_STATE_RAW" | grep "^description" | awk '{print $2}')

# Handle empty results (defaults)
SKU_WEIGHT=${SKU_WEIGHT:-1}
NAME_WEIGHT=${NAME_WEIGHT:-1}
DESC_WEIGHT=${DESC_WEIGHT:-1}

echo "Final Weights Found: SKU=$SKU_WEIGHT, Name=$NAME_WEIGHT, Description=$DESC_WEIGHT"

# 2. Get Initial State for comparison
INITIAL_SKU_WEIGHT=$(grep "^sku" /tmp/initial_search_weights.txt 2>/dev/null | awk '{print $2}')
INITIAL_SKU_WEIGHT=${INITIAL_SKU_WEIGHT:-1}

INITIAL_NAME_WEIGHT=$(grep "^name" /tmp/initial_search_weights.txt 2>/dev/null | awk '{print $2}')
INITIAL_NAME_WEIGHT=${INITIAL_NAME_WEIGHT:-1}

INITIAL_DESC_WEIGHT=$(grep "^description" /tmp/initial_search_weights.txt 2>/dev/null | awk '{print $2}')
INITIAL_DESC_WEIGHT=${INITIAL_DESC_WEIGHT:-1}

# 3. Check for Anti-Gaming (Did values change?)
CHANGED_SKU="false"
[ "$SKU_WEIGHT" != "$INITIAL_SKU_WEIGHT" ] && CHANGED_SKU="true"

CHANGED_NAME="false"
[ "$NAME_WEIGHT" != "$INITIAL_NAME_WEIGHT" ] && CHANGED_NAME="true"

CHANGED_DESC="false"
[ "$DESC_WEIGHT" != "$INITIAL_DESC_WEIGHT" ] && CHANGED_DESC="true"

# 4. Construct JSON Result
TEMP_JSON=$(mktemp /tmp/search_relevance_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "weights": {
        "sku": "$SKU_WEIGHT",
        "name": "$NAME_WEIGHT",
        "description": "$DESC_WEIGHT"
    },
    "initial_weights": {
        "sku": "$INITIAL_SKU_WEIGHT",
        "name": "$INITIAL_NAME_WEIGHT",
        "description": "$INITIAL_DESC_WEIGHT"
    },
    "changes_detected": {
        "sku": $CHANGED_SKU,
        "name": $CHANGED_NAME,
        "description": $CHANGED_DESC
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Save to final location
safe_write_json "$TEMP_JSON" /tmp/search_relevance_result.json

echo "Result JSON content:"
cat /tmp/search_relevance_result.json
echo ""
echo "=== Export Complete ==="