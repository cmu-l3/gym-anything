#!/bin/bash
set -e
echo "=== Exporting Flag Low Stock Items Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png ga

# 2. DB Connectivity Check
if ! check_db_connection; then
    echo "ERROR: Database unreachable"
    echo '{"error": "database_unreachable"}' > /tmp/task_result.json
    exit 1
fi

# 3. Data Extraction
echo "Extracting verification data..."

# Check if tag exists
TAG_EXISTS="false"
TAG_ID=$(wc_query "SELECT term_id FROM wp_terms WHERE name='Urgent Reorder' LIMIT 1")

if [ -n "$TAG_ID" ]; then
    TAG_EXISTS="true"
    TERM_TAX_ID=$(wc_query "SELECT term_taxonomy_id FROM wp_term_taxonomy WHERE term_id=$TAG_ID AND taxonomy='product_tag'")
else
    TERM_TAX_ID=""
fi

# Helper to check if a product has the tag
# Args: $1=ProductTitle
check_product_tag() {
    local title="$1"
    local has_tag="false"
    
    if [ -n "$TERM_TAX_ID" ]; then
        local pid=$(wc_query "SELECT ID FROM wp_posts WHERE post_title='$title' AND post_type='product' LIMIT 1")
        if [ -n "$pid" ]; then
            local count=$(wc_query "SELECT COUNT(*) FROM wp_term_relationships WHERE object_id=$pid AND term_taxonomy_id=$TERM_TAX_ID")
            if [ "$count" -gt "0" ]; then
                has_tag="true"
            fi
        fi
    fi
    echo "$has_tag"
}

# Check targets
BEANIE_TAGGED=$(check_product_tag "Beanie")
CAP_TAGGED=$(check_product_tag "Cap")
BELT_TAGGED=$(check_product_tag "Belt")
SUNGLASSES_TAGGED=$(check_product_tag "Sunglasses")
TEE_TAGGED=$(check_product_tag "Long Sleeve Tee")

# 4. JSON Construction
# Note: Python isn't always available with 'json' module in minimal envs, 
# so we construct JSON manually or use python3 -c if available. 
# Here we use a safe heredoc approach.

cat > /tmp/task_result.json <<EOF
{
  "tag_exists": $TAG_EXISTS,
  "tag_id": "${TAG_ID:-null}",
  "results": {
    "Beanie": $BEANIE_TAGGED,
    "Cap": $CAP_TAGGED,
    "Belt": $BELT_TAGGED,
    "Sunglasses": $SUNGLASSES_TAGGED,
    "Long Sleeve Tee": $TEE_TAGGED
  },
  "metadata": {
    "expected_low": ["Beanie", "Cap", "Belt"],
    "expected_high": ["Sunglasses", "Long Sleeve Tee"]
  },
  "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="