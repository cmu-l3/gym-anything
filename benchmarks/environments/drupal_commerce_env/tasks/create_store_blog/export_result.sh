#!/bin/bash
# Export script for Create Store Blog task
echo "=== Exporting Create Store Blog Result ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type drupal_db_query &>/dev/null; then
    drupal_db_query() {
        docker exec drupal-mariadb mysql -u drupal -pdrupalpass drupal -N -e "$1" 2>/dev/null
    }
fi
if ! type json_escape &>/dev/null; then
    json_escape() {
        echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr -d '\n' | tr -d '\r'
    }
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 1. Check for Content Type
echo "Checking content type..."
CT_EXISTS="false"
CT_CHECK=$(drupal_db_query "SELECT COUNT(*) FROM config WHERE name = 'node.type.store_blog_post'")
if [ "$CT_CHECK" -gt 0 ]; then
    CT_EXISTS="true"
fi

# 2. Check for Vocabulary
echo "Checking vocabulary..."
VOCAB_EXISTS="false"
VOCAB_CHECK=$(drupal_db_query "SELECT COUNT(*) FROM config WHERE name = 'taxonomy.vocabulary.blog_categories'")
if [ "$VOCAB_CHECK" -gt 0 ]; then
    VOCAB_EXISTS="true"
fi

# 3. Check for Terms
echo "Checking taxonomy terms..."
TERMS_FOUND=""
# Get all terms in the vocabulary (vid is stored in the data table)
TERMS_DATA=$(drupal_db_query "SELECT name FROM taxonomy_term_field_data WHERE vid = 'blog_categories'")
# Convert newlines to comma-separated for JSON
TERMS_FOUND=$(echo "$TERMS_DATA" | tr '\n' ',' | sed 's/,$//')

# 4. Check for Fields
echo "Checking fields..."
FIELD_PRODUCT_EXISTS="false"
FIELD_CATEGORY_EXISTS="false"

# Check field storage config
FP_CHECK=$(drupal_db_query "SELECT COUNT(*) FROM config WHERE name = 'field.storage.node.field_featured_product'")
if [ "$FP_CHECK" -gt 0 ]; then
    FIELD_PRODUCT_EXISTS="true"
fi

BC_CHECK=$(drupal_db_query "SELECT COUNT(*) FROM config WHERE name = 'field.storage.node.field_blog_category'")
if [ "$BC_CHECK" -gt 0 ]; then
    FIELD_CATEGORY_EXISTS="true"
fi

# 5. Check for the Blog Post Node
echo "Checking blog post..."
NODE_FOUND="false"
NODE_TITLE=""
NODE_STATUS=""
NODE_ID=""
TARGET_PRODUCT_TITLE=""
TARGET_TERM_NAME=""

# Find node of type store_blog_post created after task start
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
NODE_DATA=$(drupal_db_query "SELECT nid, title, status FROM node_field_data WHERE type = 'store_blog_post' AND created >= $TASK_START ORDER BY nid DESC LIMIT 1")

if [ -n "$NODE_DATA" ]; then
    NODE_FOUND="true"
    NODE_ID=$(echo "$NODE_DATA" | cut -f1)
    NODE_TITLE=$(echo "$NODE_DATA" | cut -f2)
    NODE_STATUS=$(echo "$NODE_DATA" | cut -f3)

    # Check Referenced Product
    # The table name for the field is usually node__field_name
    PROD_REF_ID=$(drupal_db_query "SELECT field_featured_product_target_id FROM node__field_featured_product WHERE entity_id = $NODE_ID LIMIT 1")
    if [ -n "$PROD_REF_ID" ]; then
        TARGET_PRODUCT_TITLE=$(drupal_db_query "SELECT title FROM commerce_product_field_data WHERE product_id = $PROD_REF_ID")
    fi

    # Check Referenced Category
    TERM_REF_ID=$(drupal_db_query "SELECT field_blog_category_target_id FROM node__field_blog_category WHERE entity_id = $NODE_ID LIMIT 1")
    if [ -n "$TERM_REF_ID" ]; then
        TARGET_TERM_NAME=$(drupal_db_query "SELECT name FROM taxonomy_term_field_data WHERE tid = $TERM_REF_ID")
    fi
fi

# 6. Check View
echo "Checking View URL..."
VIEW_URL_STATUS="000"
VIEW_URL_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/store-blog)

# Also check config for view existence
VIEW_CONFIG_EXISTS="false"
VIEW_CHECK=$(drupal_db_query "SELECT COUNT(*) FROM config WHERE name LIKE 'views.view.%' AND data LIKE '%store-blog%'")
if [ "$VIEW_CHECK" -gt 0 ]; then
    VIEW_CONFIG_EXISTS="true"
fi

# Construct JSON
cat > /tmp/task_result.json << EOF
{
    "content_type_exists": $CT_EXISTS,
    "vocabulary_exists": $VOCAB_EXISTS,
    "terms_found": "$(json_escape "$TERMS_FOUND")",
    "field_featured_product_exists": $FIELD_PRODUCT_EXISTS,
    "field_blog_category_exists": $FIELD_CATEGORY_EXISTS,
    "node_found": $NODE_FOUND,
    "node_title": "$(json_escape "$NODE_TITLE")",
    "node_status": "${NODE_STATUS:-0}",
    "referenced_product": "$(json_escape "$TARGET_PRODUCT_TITLE")",
    "referenced_category": "$(json_escape "$TARGET_TERM_NAME")",
    "view_http_status": $VIEW_URL_STATUS,
    "view_config_exists": $VIEW_CONFIG_EXISTS,
    "timestamp": $(date +%s)
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="