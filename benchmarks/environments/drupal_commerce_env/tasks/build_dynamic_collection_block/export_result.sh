#!/bin/bash
# Export script for build_dynamic_collection_block
echo "=== Exporting Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot (frontend)
navigate_firefox_to "http://localhost/" 10
sleep 5
take_screenshot /tmp/task_end_screenshot.png

# 1. Check Vocabulary
VOCAB_EXISTS=$(drupal_db_query "SELECT COUNT(*) FROM config WHERE name = 'taxonomy.vocabulary.collections'" 2>/dev/null || echo "0")
echo "Vocab exists count: $VOCAB_EXISTS"

# 2. Check Term
TERM_ID=$(drupal_db_query "SELECT tid FROM taxonomy_term_field_data WHERE name = 'Summer Collection' LIMIT 1" 2>/dev/null)
TERM_EXISTS="false"
if [ -n "$TERM_ID" ]; then
    TERM_EXISTS="true"
    # Verify it belongs to the correct vocabulary
    TERM_VID=$(drupal_db_query "SELECT vid FROM taxonomy_term_data WHERE tid = $TERM_ID" 2>/dev/null)
    echo "Term ID: $TERM_ID (vid: $TERM_VID)"
fi

# 3. Check Field Configuration
FIELD_STORAGE_EXISTS=$(drupal_db_query "SELECT COUNT(*) FROM config WHERE name = 'field.storage.commerce_product.field_collection'" 2>/dev/null || echo "0")
FIELD_INSTANCE_EXISTS=$(drupal_db_query "SELECT COUNT(*) FROM config WHERE name = 'field.field.commerce_product.default.field_collection'" 2>/dev/null || echo "0")
echo "Field storage: $FIELD_STORAGE_EXISTS, Field instance: $FIELD_INSTANCE_EXISTS"

# 4. Check Product Tagging
TAGGED_COUNT=0
SONY_TAGGED="false"
LOGI_TAGGED="false"

# Get IDs for target products
SONY_ID=$(get_product_id_by_title "Sony WH-1000XM5 Wireless Headphones")
LOGI_ID=$(get_product_id_by_title "Logitech MX Master 3S Wireless Mouse")

if [ -n "$SONY_ID" ] && [ -n "$TERM_ID" ]; then
    # Check commerce_product__field_collection table
    # This table only exists if the field was created successfully
    if drupal_db_query "SHOW TABLES LIKE 'commerce_product__field_collection'" | grep -q "commerce_product__field_collection"; then
        CHECK=$(drupal_db_query "SELECT COUNT(*) FROM commerce_product__field_collection WHERE entity_id = $SONY_ID AND field_collection_target_id = $TERM_ID")
        if [ "$CHECK" -gt 0 ]; then SONY_TAGGED="true"; ((TAGGED_COUNT++)); fi
        
        CHECK=$(drupal_db_query "SELECT COUNT(*) FROM commerce_product__field_collection WHERE entity_id = $LOGI_ID AND field_collection_target_id = $TERM_ID")
        if [ "$CHECK" -gt 0 ]; then LOGI_TAGGED="true"; ((TAGGED_COUNT++)); fi
    fi
fi
echo "Tagged count: $TAGGED_COUNT"

# 5. Check View Existence
VIEW_EXISTS=$(drupal_db_query "SELECT COUNT(*) FROM config WHERE name = 'views.view.summer_collection'" 2>/dev/null || echo "0")
echo "View exists: $VIEW_EXISTS"

# 6. Check Block Placement
# Look for a block placement config that uses the view
BLOCK_PLACED=$(drupal_db_query "SELECT COUNT(*) FROM config WHERE name LIKE 'block.block.olivero_%' AND data LIKE '%views_block:summer_collection%'" 2>/dev/null || echo "0")
echo "Block placed: $BLOCK_PLACED"

# 7. Frontend Verification (Scrape homepage)
HOMEPAGE_CONTENT=$(curl -s http://localhost/)
VISIBLE_ON_HOMEPAGE="false"
BLOCK_TITLE_VISIBLE="false"
PRODUCTS_VISIBLE="false"

if echo "$HOMEPAGE_CONTENT" | grep -qi "Summer Collection"; then
    BLOCK_TITLE_VISIBLE="true"
fi

if echo "$HOMEPAGE_CONTENT" | grep -q "Sony WH-1000XM5" && echo "$HOMEPAGE_CONTENT" | grep -q "Logitech MX Master 3S"; then
    PRODUCTS_VISIBLE="true"
fi

if [ "$BLOCK_TITLE_VISIBLE" = "true" ] && [ "$PRODUCTS_VISIBLE" = "true" ]; then
    VISIBLE_ON_HOMEPAGE="true"
fi

# Create result JSON
create_result_json /tmp/task_result.json \
    "vocab_exists=$VOCAB_EXISTS" \
    "term_exists=$TERM_EXISTS" \
    "term_vid=$TERM_VID" \
    "field_storage_exists=$FIELD_STORAGE_EXISTS" \
    "field_instance_exists=$FIELD_INSTANCE_EXISTS" \
    "sony_tagged=$SONY_TAGGED" \
    "logi_tagged=$LOGI_TAGGED" \
    "view_exists=$VIEW_EXISTS" \
    "block_placed=$BLOCK_PLACED" \
    "visible_on_homepage=$VISIBLE_ON_HOMEPAGE" \
    "block_title_visible=$BLOCK_TITLE_VISIBLE" \
    "products_visible_in_html=$PRODUCTS_VISIBLE"

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo ""
echo "Result JSON:"
cat /tmp/task_result.json
echo "=== Export Complete ==="