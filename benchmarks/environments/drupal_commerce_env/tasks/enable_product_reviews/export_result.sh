#!/bin/bash
# Export script for Enable Product Reviews task
echo "=== Exporting Enable Product Reviews Result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Helper variables
DRUPAL_ROOT="/var/www/html/drupal"
DRUSH="$DRUPAL_ROOT/vendor/bin/drush"
TASK_START_TIME=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
INITIAL_COMMENT_COUNT=$(cat /tmp/initial_comment_count 2>/dev/null || echo "0")

# 3. export Configuration Data using Drush (JSON format is safer than parsing DB blobs)
cd "$DRUPAL_ROOT"

# A. Check Comment Type
echo "Checking Comment Type..."
COMMENT_TYPE_JSON=$($DRUSH config:get comment.type.product_review --format=json 2>/dev/null)
if [ $? -eq 0 ] && [ -n "$COMMENT_TYPE_JSON" ]; then
    COMMENT_TYPE_EXISTS="true"
else
    COMMENT_TYPE_EXISTS="false"
    COMMENT_TYPE_JSON="{}"
fi

# B. Check Field Storage (verifies field name and entity type)
echo "Checking Field Storage..."
FIELD_STORAGE_JSON=$($DRUSH config:get field.storage.commerce_product.field_reviews --format=json 2>/dev/null)
if [ $? -eq 0 ] && [ -n "$FIELD_STORAGE_JSON" ]; then
    FIELD_STORAGE_EXISTS="true"
else
    FIELD_STORAGE_EXISTS="false"
    FIELD_STORAGE_JSON="{}"
fi

# C. Check Field Instance (verifies bundle and comment type setting)
echo "Checking Field Instance..."
FIELD_INSTANCE_JSON=$($DRUSH config:get field.field.commerce_product.default.field_reviews --format=json 2>/dev/null)
if [ $? -eq 0 ] && [ -n "$FIELD_INSTANCE_JSON" ]; then
    FIELD_INSTANCE_EXISTS="true"
else
    FIELD_INSTANCE_EXISTS="false"
    FIELD_INSTANCE_JSON="{}"
fi

# 4. Verify Content (The Test Review) via Database
# We need to find a comment with the expected subject created after start time
# and linked to the correct product.

EXPECTED_SUBJECT="Amazing Quality"
EXPECTED_SKU="SONY-WH1000XM5"

# Get Product ID for the Sony headphones
PRODUCT_ID=$(drupal_db_query "SELECT variation_id FROM commerce_product_variation_field_data WHERE sku='$EXPECTED_SKU' LIMIT 1" | \
             xargs -I {} sh -c "docker exec drupal-mariadb mysql -u drupal -pdrupalpass drupal -N -e \"SELECT entity_id FROM commerce_product__variations WHERE variations_target_id={}\"")

# If lookup failed (complex join), try direct title search
if [ -z "$PRODUCT_ID" ]; then
    PRODUCT_ID=$(drupal_db_query "SELECT product_id FROM commerce_product_field_data WHERE title LIKE '%Sony WH-1000XM5%' LIMIT 1")
fi

echo "Target Product ID: $PRODUCT_ID"

# Find the comment
# We look for:
# - Matches subject
# - entity_type is 'commerce_product' (CRITICAL: prevents posting on nodes)
# - entity_id is PRODUCT_ID
# - field_name is 'field_reviews'
COMMENT_QUERY="SELECT cid, subject, created, entity_type, field_name FROM comment_field_data WHERE subject LIKE '$EXPECTED_SUBJECT' AND entity_id='$PRODUCT_ID' ORDER BY cid DESC LIMIT 1"

COMMENT_DATA=$(drupal_db_query "$COMMENT_QUERY")

COMMENT_FOUND="false"
COMMENT_ON_PRODUCT="false"
COMMENT_CORRECT_FIELD="false"
COMMENT_TIMESTAMP=0

if [ -n "$COMMENT_DATA" ]; then
    COMMENT_FOUND="true"
    # Parse tab-separated values
    C_CID=$(echo "$COMMENT_DATA" | awk '{print $1}')
    C_SUBJECT=$(echo "$COMMENT_DATA" | awk '{print $2}') # Might be truncated if spaces, relying on LIKE in query
    C_CREATED=$(echo "$COMMENT_DATA" | awk '{print $3}')
    C_ENTITY_TYPE=$(echo "$COMMENT_DATA" | awk '{print $4}')
    C_FIELD_NAME=$(echo "$COMMENT_DATA" | awk '{print $5}')
    
    COMMENT_TIMESTAMP=$C_CREATED

    if [ "$C_ENTITY_TYPE" == "commerce_product" ]; then
        COMMENT_ON_PRODUCT="true"
    fi
    
    if [ "$C_FIELD_NAME" == "field_reviews" ]; then
        COMMENT_CORRECT_FIELD="true"
    fi
fi

# 5. Get current counts
CURRENT_COMMENT_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM comment_field_data")

# 6. Prepare Result JSON
# We use Python to robustly construct the JSON to handle potential escaping issues with the drush output
python3 -c "
import json
import os
import sys

try:
    comment_type = json.loads('''${COMMENT_TYPE_JSON}''' or '{}')
    field_storage = json.loads('''${FIELD_STORAGE_JSON}''' or '{}')
    field_instance = json.loads('''${FIELD_INSTANCE_JSON}''' or '{}')
except Exception as e:
    comment_type = {}
    field_storage = {}
    field_instance = {}
    print(f'Error parsing JSON configs: {e}', file=sys.stderr)

result = {
    'comment_type_exists': '${COMMENT_TYPE_EXISTS}' == 'true',
    'comment_type_config': comment_type,
    'field_storage_exists': '${FIELD_STORAGE_EXISTS}' == 'true',
    'field_storage_config': field_storage,
    'field_instance_exists': '${FIELD_INSTANCE_EXISTS}' == 'true',
    'field_instance_config': field_instance,
    'comment_found': '${COMMENT_FOUND}' == 'true',
    'comment_on_correct_product': '${COMMENT_ON_PRODUCT}' == 'true',
    'comment_on_correct_field': '${COMMENT_CORRECT_FIELD}' == 'true',
    'comment_timestamp': int('${COMMENT_TIMESTAMP}'),
    'task_start_time': int('${TASK_START_TIME}'),
    'initial_comment_count': int('${INITIAL_COMMENT_COUNT}'),
    'current_comment_count': int('${CURRENT_COMMENT_COUNT}')
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Set permissions
chmod 666 /tmp/task_result.json

echo "Result JSON generated at /tmp/task_result.json"
echo "=== Export Complete ==="