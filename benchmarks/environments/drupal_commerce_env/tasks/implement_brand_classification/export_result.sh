#!/bin/bash
# Export script for implement_brand_classification task

echo "=== Exporting Implement Brand Classification Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 1. Check if Vocabulary 'brands' exists
# In config table, name should be 'taxonomy.vocabulary.brands'
VOCAB_EXISTS="false"
VOCAB_CHECK=$(drupal_db_query "SELECT name FROM config WHERE name = 'taxonomy.vocabulary.brands'" 2>/dev/null)
if [ -n "$VOCAB_CHECK" ]; then
    VOCAB_EXISTS="true"
fi

# 2. Check Terms (Sony, Logitech, Google)
# Join taxonomy_term_field_data with taxonomy_vocabulary (but vocab is config entity in D8+, 
# usually terms link to vid string in field_data)
TERMS_FOUND_COUNT=0
TERMS_LIST=""
for TERM in "Sony" "Logitech" "Google"; do
    COUNT=$(drupal_db_query "SELECT COUNT(*) FROM taxonomy_term_field_data WHERE vid = 'brands' AND name = '$TERM'" 2>/dev/null || echo "0")
    if [ "$COUNT" -gt 0 ]; then
        TERMS_FOUND_COUNT=$((TERMS_FOUND_COUNT + 1))
        TERMS_LIST="${TERMS_LIST}${TERM},"
    fi
done

# 3. Check Field Storage (commerce_product.field_brand)
# Config: field.storage.commerce_product.field_brand
FIELD_STORAGE_EXISTS="false"
FIELD_CARDINALITY=""
FIELD_TARGET_TYPE=""

STORAGE_CONFIG=$(drupal_db_query "SELECT data FROM config WHERE name = 'field.storage.commerce_product.field_brand'" 2>/dev/null)
if [ -n "$STORAGE_CONFIG" ]; then
    FIELD_STORAGE_EXISTS="true"
    # Basic check using grep on serialized data/blob
    if echo "$STORAGE_CONFIG" | grep -q "cardinality"; then
        # Check cardinality is 1
        if echo "$STORAGE_CONFIG" | grep -q 'i:1;'; then
             FIELD_CARDINALITY="1"
        fi
    fi
    if echo "$STORAGE_CONFIG" | grep -q "taxonomy_term"; then
        FIELD_TARGET_TYPE="taxonomy_term"
    fi
fi

# 4. Check Field Instance (commerce_product.default.field_brand)
# Config: field.field.commerce_product.default.field_brand
FIELD_INSTANCE_EXISTS="false"
INSTANCE_CONFIG=$(drupal_db_query "SELECT name FROM config WHERE name = 'field.field.commerce_product.default.field_brand'" 2>/dev/null)
if [ -n "$INSTANCE_CONFIG" ]; then
    FIELD_INSTANCE_EXISTS="true"
fi

# 5. Check Form Display
# Config: core.entity_form_display.commerce_product.default.default
FORM_DISPLAY_CONFIGURED="false"
FORM_DISPLAY_DATA=$(drupal_db_query "SELECT data FROM config WHERE name = 'core.entity_form_display.commerce_product.default.default'" 2>/dev/null)
if echo "$FORM_DISPLAY_DATA" | grep -q "field_brand"; then
    FORM_DISPLAY_CONFIGURED="true"
fi

# 6. Check View Display
# Config: core.entity_view_display.commerce_product.default.default
VIEW_DISPLAY_CONFIGURED="false"
VIEW_DISPLAY_DATA=$(drupal_db_query "SELECT data FROM config WHERE name = 'core.entity_view_display.commerce_product.default.default'" 2>/dev/null)
if echo "$VIEW_DISPLAY_DATA" | grep -q "field_brand"; then
    VIEW_DISPLAY_CONFIGURED="true"
fi

# 7. Check Product Tagging (Sony and Logitech)
SONY_TAGGED="false"
LOGI_TAGGED="false"

# Find Product IDs
SONY_PID=$(get_product_id_by_title "Sony WH-1000XM5 Wireless Headphones")
LOGI_PID=$(get_product_id_by_title "Logitech MX Master 3S Wireless Mouse")

# Find Term IDs
SONY_TID=$(drupal_db_query "SELECT tid FROM taxonomy_term_field_data WHERE vid = 'brands' AND name = 'Sony' LIMIT 1" 2>/dev/null)
LOGI_TID=$(drupal_db_query "SELECT tid FROM taxonomy_term_field_data WHERE vid = 'brands' AND name = 'Logitech' LIMIT 1" 2>/dev/null)

if [ -n "$SONY_PID" ] && [ -n "$SONY_TID" ]; then
    # Check if entry exists in commerce_product__field_brand
    # Table structure: bundle, deleted, entity_id, revision_id, langcode, delta, field_brand_target_id
    CHECK=$(drupal_db_query "SELECT COUNT(*) FROM commerce_product__field_brand WHERE entity_id = $SONY_PID AND field_brand_target_id = $SONY_TID" 2>/dev/null || echo "0")
    if [ "$CHECK" -gt 0 ]; then
        SONY_TAGGED="true"
    fi
fi

if [ -n "$LOGI_PID" ] && [ -n "$LOGI_TID" ]; then
    CHECK=$(drupal_db_query "SELECT COUNT(*) FROM commerce_product__field_brand WHERE entity_id = $LOGI_PID AND field_brand_target_id = $LOGI_TID" 2>/dev/null || echo "0")
    if [ "$CHECK" -gt 0 ]; then
        LOGI_TAGGED="true"
    fi
fi

# JSON export
create_result_json /tmp/task_result.json \
    "vocab_exists=$VOCAB_EXISTS" \
    "terms_found_count=$TERMS_FOUND_COUNT" \
    "terms_list=$(json_escape "$TERMS_LIST")" \
    "field_storage_exists=$FIELD_STORAGE_EXISTS" \
    "field_cardinality=$(json_escape "$FIELD_CARDINALITY")" \
    "field_target_type=$(json_escape "$FIELD_TARGET_TYPE")" \
    "field_instance_exists=$FIELD_INSTANCE_EXISTS" \
    "form_display_configured=$FORM_DISPLAY_CONFIGURED" \
    "view_display_configured=$VIEW_DISPLAY_CONFIGURED" \
    "sony_tagged=$SONY_TAGGED" \
    "logitech_tagged=$LOGI_TAGGED"

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON:"
cat /tmp/task_result.json

echo "=== Export Complete ==="