#!/bin/bash
# Export script for Product Reviews & Ratings task

echo "=== Exporting Product Reviews & Ratings Result ==="

source /workspace/scripts/task_utils.sh
take_screenshot /tmp/task_end_screenshot.png

INITIAL_RATING_COUNT=$(cat /tmp/initial_rating_count 2>/dev/null || echo "0")
INITIAL_REVIEW_COUNT=$(cat /tmp/initial_review_count 2>/dev/null || echo "0")

CURRENT_RATING_COUNT=$(magento_query "SELECT COUNT(*) FROM rating" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
CURRENT_REVIEW_COUNT=$(magento_query "SELECT COUNT(*) FROM review" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")

# 1. Check Rating "Durability"
RATING_DATA=$(magento_query "SELECT rating_id, rating_code FROM rating WHERE LOWER(TRIM(rating_code))='durability'" 2>/dev/null | tail -1)
RATING_ID=$(echo "$RATING_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
RATING_CODE=$(echo "$RATING_DATA" | awk -F'\t' '{print $2}')

RATING_FOUND="false"
[ -n "$RATING_ID" ] && RATING_FOUND="true"

# Check if visible in default store (store_id=1)
RATING_VISIBLE="false"
if [ -n "$RATING_ID" ]; then
    STORE_CHECK=$(magento_query "SELECT COUNT(*) FROM rating_store WHERE rating_id=$RATING_ID AND store_id=1" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
    if [ "$STORE_CHECK" -gt "0" ]; then
        RATING_VISIBLE="true"
    fi
fi
echo "Rating 'Durability': found=$RATING_FOUND visible=$RATING_VISIBLE id=$RATING_ID"

# 2. Check Reviews
# Helper to check a single review
check_review() {
    local nickname="$1"
    local sku="$2"
    local expected_fragment="$3"
    
    # Get product ID
    local prod_id=$(magento_query "SELECT entity_id FROM catalog_product_entity WHERE sku='$sku'" 2>/dev/null | tail -1 | tr -d '[:space:]')
    
    if [ -z "$prod_id" ]; then
        echo "null"
        return
    fi

    # Find review by nickname and product
    # We join review and review_detail
    local query="SELECT r.review_id, r.status_id, d.title, d.detail 
                 FROM review r 
                 JOIN review_detail d ON r.review_id = d.review_id 
                 WHERE r.entity_pk_value = $prod_id 
                 AND d.nickname = '$nickname' 
                 ORDER BY r.review_id DESC LIMIT 1"
                 
    local result=$(magento_query "$query" 2>/dev/null | tail -1)
    
    if [ -z "$result" ]; then
        echo "null"
        return
    fi
    
    local review_id=$(echo "$result" | awk -F'\t' '{print $1}')
    local status_id=$(echo "$result" | awk -F'\t' '{print $2}')
    local title=$(echo "$result" | awk -F'\t' '{print $3}')
    # Note: detail might be truncated by awk if it contains tabs/newlines, but title is usually safe enough
    
    # Get votes
    # rating_option_vote table: review_id, option_id
    # rating_option table: option_id, rating_id, value (1-5)
    # rating table: rating_id, rating_code
    local votes_query="SELECT rg.rating_code, ro.value 
                       FROM rating_option_vote rov 
                       JOIN rating_option ro ON rov.option_id = ro.option_id 
                       JOIN rating rg ON ro.rating_id = rg.rating_id 
                       WHERE rov.review_id = $review_id"
                       
    local votes_raw=$(magento_query "$votes_query" 2>/dev/null)
    # Format votes as JSON object string e.g. {"Quality": 5, "Price": 4}
    local votes_json=$(echo "$votes_raw" | awk -F'\t' '{printf "\"%s\": %s, ", $1, $2}' | sed 's/, $//')
    
    echo "{\"id\": \"$review_id\", \"status_id\": \"$status_id\", \"title\": \"$title\", \"votes\": {$votes_json}}"
}

REVIEW_1=$(check_review "TechBuyer42" "LAPTOP-001" "Excellent")
REVIEW_2=$(check_review "AudioFan" "HEADPHONES-001" "Great sound")
REVIEW_3=$(check_review "FitnessPro" "YOGA-001" "Perfect")

echo "Reviews check complete."

# Prepare JSON
TEMP_JSON=$(mktemp /tmp/reviews_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_rating_count": ${INITIAL_RATING_COUNT:-0},
    "current_rating_count": ${CURRENT_RATING_COUNT:-0},
    "initial_review_count": ${INITIAL_REVIEW_COUNT:-0},
    "current_review_count": ${CURRENT_REVIEW_COUNT:-0},
    "rating_found": $RATING_FOUND,
    "rating_visible": $RATING_VISIBLE,
    "rating_id": "${RATING_ID:-}",
    "reviews": {
        "review_1": $REVIEW_1,
        "review_2": $REVIEW_2,
        "review_3": $REVIEW_3
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/reviews_result.json

echo ""
cat /tmp/reviews_result.json
echo ""
echo "=== Export Complete ==="