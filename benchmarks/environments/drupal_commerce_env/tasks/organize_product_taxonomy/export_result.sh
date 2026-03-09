#!/bin/bash
# Export script for organize_product_taxonomy task
echo "=== Exporting organize_product_taxonomy Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# ==============================================================================
# DATA EXTRACTION
# ==============================================================================

# 1. Check if Vocabulary exists (via config table)
VOCAB_EXISTS="false"
VOCAB_CHECK=$(drupal_db_query "SELECT COUNT(*) FROM config WHERE name = 'taxonomy.vocabulary.product_categories'")
if [ "$VOCAB_CHECK" -gt 0 ]; then
    VOCAB_EXISTS="true"
fi

# 2. Get list of Terms in this vocabulary
# We query taxonomy_term_field_data filtering by vid='product_categories'
TERMS_JSON="[]"
if [ "$VOCAB_EXISTS" = "true" ]; then
    # Get names, newline separated
    TERM_NAMES=$(drupal_db_query "SELECT name FROM taxonomy_term_field_data WHERE vid = 'product_categories' AND status = 1")
    
    # Convert to JSON array safely
    if [ -n "$TERM_NAMES" ]; then
        # Python to format list as JSON array
        TERMS_JSON=$(echo "$TERM_NAMES" | python3 -c "import sys, json; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))")
    fi
fi

# 3. Check if Field exists on Commerce Product
# Check config for field storage and field instance
FIELD_STORAGE_EXISTS=$(drupal_db_query "SELECT COUNT(*) FROM config WHERE name = 'field.storage.commerce_product.field_category'")
FIELD_INSTANCE_EXISTS=$(drupal_db_query "SELECT COUNT(*) FROM config WHERE name = 'field.field.commerce_product.default.field_category'")

FIELD_CONFIG_VALID="false"
if [ "$FIELD_STORAGE_EXISTS" -gt 0 ] && [ "$FIELD_INSTANCE_EXISTS" -gt 0 ]; then
    FIELD_CONFIG_VALID="true"
fi

# 4. Check Product Assignments
# We need to join the product table, the field table, and the term table
# Note: The field table name is usually 'commerce_product__field_category'
TABLE_EXISTS=$(drupal_db_query "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'drupal' AND table_name = 'commerce_product__field_category'")

ASSIGNMENTS="{}"
if [ "$TABLE_EXISTS" -gt 0 ]; then
    # Query: Product Title -> Term Name
    # We target the two specific products we care about
    ASSIGNMENT_DATA=$(drupal_db_query "
        SELECT p.title, t.name 
        FROM commerce_product__field_category fc 
        JOIN commerce_product_field_data p ON fc.entity_id = p.product_id 
        JOIN taxonomy_term_field_data t ON fc.field_category_target_id = t.tid 
        WHERE p.title IN ('Sony WH-1000XM5 Wireless Headphones', 'Logitech MX Master 3S Wireless Mouse')
    ")
    
    # Convert TSV to JSON object
    if [ -n "$ASSIGNMENT_DATA" ]; then
        ASSIGNMENTS=$(echo "$ASSIGNMENT_DATA" | python3 -c "
import sys, json
data = {}
for line in sys.stdin:
    parts = line.strip().split('\t')
    if len(parts) >= 2:
        data[parts[0]] = parts[1]
print(json.dumps(data))
")
    fi
fi

# 5. Check field type (anti-gaming: ensure it is entity_reference, not just text)
FIELD_TYPE=""
if [ "$FIELD_STORAGE_EXISTS" -gt 0 ]; then
    # The config data is a serialized blob, but often we can just check 'type: entity_reference' string in it
    # Or query key_value table if using D8 state, but config table is reliable for definitions
    # Let's check the config data blob for 'entity_reference'
    CONFIG_DATA=$(drupal_db_query "SELECT CAST(data AS CHAR) FROM config WHERE name = 'field.storage.commerce_product.field_category'")
    if echo "$CONFIG_DATA" | grep -q "entity_reference"; then
        FIELD_TYPE="entity_reference"
    elif echo "$CONFIG_DATA" | grep -q "list_string"; then
        FIELD_TYPE="list_string"
    else
        FIELD_TYPE="unknown"
    fi
fi

# ==============================================================================
# JSON OUTPUT
# ==============================================================================
cat > /tmp/task_result.json << EOF
{
    "vocab_exists": $VOCAB_EXISTS,
    "terms": $TERMS_JSON,
    "field_exists": $FIELD_CONFIG_VALID,
    "field_type": "$FIELD_TYPE",
    "assignments": $ASSIGNMENTS,
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON:"
cat /tmp/task_result.json
echo "=== Export Complete ==="