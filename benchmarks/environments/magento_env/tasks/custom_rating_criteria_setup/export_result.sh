#!/bin/bash
# Export script for Custom Rating Criteria task

echo "=== Exporting Custom Rating Criteria Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get counts
INITIAL_COUNT=$(cat /tmp/initial_rating_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(magento_query "SELECT COUNT(*) FROM rating" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")

# Helper function to extract rating details by name
get_rating_details() {
    local name="$1"
    # Query joins: rating -> rating_title (for name) AND rating -> rating_store (for visibility)
    # We use GROUP_CONCAT on store_id to handle cases where it might be assigned to multiple stores
    local query="
        SELECT 
            r.rating_id, 
            r.is_active, 
            r.position, 
            t.value as title,
            GROUP_CONCAT(rs.store_id) as store_ids
        FROM rating r
        JOIN rating_title t ON r.rating_id = t.rating_id
        LEFT JOIN rating_store rs ON r.rating_id = rs.rating_id
        WHERE LOWER(TRIM(t.value)) = LOWER(TRIM('$name'))
        GROUP BY r.rating_id, r.is_active, r.position, t.value
        ORDER BY r.rating_id DESC 
        LIMIT 1
    "
    magento_query "$query" 2>/dev/null | tail -1
}

# Check "Fit Accuracy"
FIT_DATA=$(get_rating_details "Fit Accuracy")
FIT_FOUND="false"
if [ -n "$FIT_DATA" ]; then
    FIT_FOUND="true"
    FIT_ID=$(echo "$FIT_DATA" | awk -F'\t' '{print $1}')
    FIT_ACTIVE=$(echo "$FIT_DATA" | awk -F'\t' '{print $2}')
    FIT_POS=$(echo "$FIT_DATA" | awk -F'\t' '{print $3}')
    FIT_STORES=$(echo "$FIT_DATA" | awk -F'\t' '{print $5}')
fi

# Check "Material Quality"
MAT_DATA=$(get_rating_details "Material Quality")
MAT_FOUND="false"
if [ -n "$MAT_DATA" ]; then
    MAT_FOUND="true"
    MAT_ID=$(echo "$MAT_DATA" | awk -F'\t' '{print $1}')
    MAT_ACTIVE=$(echo "$MAT_DATA" | awk -F'\t' '{print $2}')
    MAT_POS=$(echo "$MAT_DATA" | awk -F'\t' '{print $3}')
    MAT_STORES=$(echo "$MAT_DATA" | awk -F'\t' '{print $5}')
fi

echo "Fit Accuracy: Found=$FIT_FOUND ID=${FIT_ID} Active=${FIT_ACTIVE} Pos=${FIT_POS} Stores=${FIT_STORES}"
echo "Material Quality: Found=$MAT_FOUND ID=${MAT_ID} Active=${MAT_ACTIVE} Pos=${MAT_POS} Stores=${MAT_STORES}"

# Create JSON result
TEMP_JSON=$(mktemp /tmp/rating_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_count": ${INITIAL_COUNT:-0},
    "current_count": ${CURRENT_COUNT:-0},
    "fit_accuracy": {
        "found": $FIT_FOUND,
        "id": "${FIT_ID:-}",
        "is_active": "${FIT_ACTIVE:-0}",
        "position": "${FIT_POS:-0}",
        "store_ids": "${FIT_STORES:-}"
    },
    "material_quality": {
        "found": $MAT_FOUND,
        "id": "${MAT_ID:-}",
        "is_active": "${MAT_ACTIVE:-0}",
        "position": "${MAT_POS:-0}",
        "store_ids": "${MAT_STORES:-}"
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/rating_result.json

echo "Result saved to /tmp/rating_result.json"