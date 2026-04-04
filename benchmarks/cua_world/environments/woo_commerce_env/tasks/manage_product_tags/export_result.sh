#!/bin/bash
echo "=== Exporting manage_product_tags results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Check DB connection
if ! check_db_connection; then
    echo '{"error": "database_unreachable"}' > /tmp/task_result.json
    exit 1
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 1. Get Tag Information
# We look for the tags by name
get_tag_info() {
    local name="$1"
    local id
    id=$(wc_query "SELECT t.term_id FROM wp_terms t JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id WHERE tt.taxonomy = 'product_tag' AND LOWER(TRIM(t.name)) = LOWER(TRIM('$name')) LIMIT 1")
    if [ -n "$id" ]; then
        echo "{\"name\": \"$name\", \"found\": true, \"id\": $id}"
    else
        echo "{\"name\": \"$name\", \"found\": false, \"id\": null}"
    fi
}

TAG_PREMIUM=$(get_tag_info "Premium")
TAG_ECO=$(get_tag_info "Eco-Friendly")
TAG_GIFT=$(get_tag_info "Gift Idea")

# 2. Get Product Information
get_product_id() {
    local name="$1"
    wc_query "SELECT ID FROM wp_posts WHERE post_type='product' AND post_status='publish' AND post_title LIKE '%$name%' LIMIT 1"
}

ID_TSHIRT=$(get_product_id "Organic Cotton T-Shirt")
ID_HEADPHONES=$(get_product_id "Wireless Bluetooth Headphones")
ID_SWEATER=$(get_product_id "Merino Wool Sweater")

# 3. Check Assignments
# Function checks if a product ID has a tag name assigned
check_assignment() {
    local pid="$1"
    local tag_name="$2"
    
    if [ -z "$pid" ]; then
        echo "false"
        return
    fi

    # Subquery to get term_id from name, then check relationship
    local count
    count=$(wc_query "SELECT COUNT(*) 
        FROM wp_term_relationships tr
        JOIN wp_term_taxonomy tt ON tr.term_taxonomy_id = tt.term_taxonomy_id
        JOIN wp_terms t ON tt.term_id = t.term_id
        WHERE tr.object_id = $pid
        AND tt.taxonomy = 'product_tag'
        AND LOWER(TRIM(t.name)) = LOWER(TRIM('$tag_name'))")
    
    if [ "$count" -gt "0" ]; then
        echo "true"
    else
        echo "false"
    fi
}

# T-Shirt Assignments
TSHIRT_HAS_PREMIUM=$(check_assignment "$ID_TSHIRT" "Premium")
TSHIRT_HAS_ECO=$(check_assignment "$ID_TSHIRT" "Eco-Friendly")

# Headphones Assignments
PHONES_HAS_PREMIUM=$(check_assignment "$ID_HEADPHONES" "Premium")
PHONES_HAS_GIFT=$(check_assignment "$ID_HEADPHONES" "Gift Idea")

# Sweater Assignments
SWEATER_HAS_ECO=$(check_assignment "$ID_SWEATER" "Eco-Friendly")
SWEATER_HAS_GIFT=$(check_assignment "$ID_SWEATER" "Gift Idea")

# 4. Anti-gaming counts
INITIAL_TAG_COUNT=$(cat /tmp/initial_tag_count.txt 2>/dev/null || echo "0")
CURRENT_TAG_COUNT=$(wc_query "SELECT COUNT(*) FROM wp_terms t JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id WHERE tt.taxonomy = 'product_tag'" 2>/dev/null || echo "0")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_tag_count": $INITIAL_TAG_COUNT,
    "current_tag_count": $CURRENT_TAG_COUNT,
    "tags": {
        "premium": $TAG_PREMIUM,
        "eco": $TAG_ECO,
        "gift": $TAG_GIFT
    },
    "products": {
        "tshirt_id": "${ID_TSHIRT:-null}",
        "headphones_id": "${ID_HEADPHONES:-null}",
        "sweater_id": "${ID_SWEATER:-null}"
    },
    "assignments": {
        "tshirt_premium": $TSHIRT_HAS_PREMIUM,
        "tshirt_eco": $TSHIRT_HAS_ECO,
        "headphones_premium": $PHONES_HAS_PREMIUM,
        "headphones_gift": $PHONES_HAS_GIFT,
        "sweater_eco": $SWEATER_HAS_ECO,
        "sweater_gift": $SWEATER_HAS_GIFT
    }
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="